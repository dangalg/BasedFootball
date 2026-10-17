#!/usr/bin/env node
// Attach-only WGC recording for the isolated historical recovery. No engine
// launch, input injection, viewport readback, pause command or replay occurs here.
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { deflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const options = {};
for (let index = 2; index < process.argv.length; index += 2) {
  if (!process.argv[index]?.startsWith('--') || process.argv[index + 1] === undefined) throw Error('Use --name value arguments.');
  options[process.argv[index].slice(2)] = process.argv[index + 1];
}
if (options.attach !== 'true') throw Error('Use --attach true. The owner launches the recovered executable.');
const session = path.resolve(project, options.session || 'evidence/recovery-match-r1');
function insideProject(absolute) {
  const relative = path.relative(project, absolute);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw Error(`Path must be beneath the recovery project: ${absolute}`);
  return relative.replaceAll('\\', '/');
}
insideProject(session);
const evidenceRelative = path.relative(path.join(project, 'evidence'), session);
if (!evidenceRelative || evidenceRelative.startsWith('..') || path.isAbsolute(evidenceRelative)) throw Error('Session must be beneath project/evidence.');
if (fs.existsSync(session) && fs.readdirSync(session).length) throw Error('Refusing to overwrite nonempty evidence.');
const wallCap = Number(options['max-wall-seconds'] || 900);
if (!Number.isFinite(wallCap) || wallCap < 60 || wallCap > 3600) throw Error('max-wall-seconds must be 60..3600.');
fs.mkdirSync(session, { recursive: true });
const filename = name => path.join(session, name);
const exists = name => fs.existsSync(filename(name));
const read = name => JSON.parse(fs.readFileSync(filename(name), 'utf8'));
function write(name, value) {
  const target = filename(name), temporary = `${target}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2)); fs.renameSync(temporary, target);
}
const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const palette = [[36, 211, 200], [255, 157, 60], [211, 70, 209], [168, 224, 67]];
const token = randomBytes(12).toString('hex');
const identityPhases = Array.from({ length: 12 }, (_, index) => (parseInt(token.slice(0, 6), 16) >> (index * 2)) & 3);
const sourcePaths = ['project.godot', 'export_presets.cfg', 'scripts', 'scenes', 'data', 'assets', 'tests', 'tools'];
const manifest = {
  schema: 'based-football-recovery-capture/v1', created_at: new Date().toISOString(), project, session,
  scene: 'recovery_full_match', capture_token: token, wall_safety_cap_seconds: wallCap,
  scope: 'One full match in the isolated recovered historical game. Capture integrity and recorded match events are separate from subjective football quality.',
  recording: { file: 'continuous.mp4', method: 'Windows Graphics Capture / exact HWND', target_fps: 30, preflight_verified: false },
  observation_policy: 'One WGC stream records continuously. Owner reviews its saved preflight image before action. Recorder sends no native screenshots, viewport readbacks, input or pause commands during action. This does not audit other tools.',
  visual_verdict: 'pending actual footage review', gameplay_verdict: 'pending saved full-match result and footage review'
};
write('manifest.json', manifest);
write('capture-request.json', { schema: 'based-football-recovery-capture-request/v1', scene: manifest.scene,
  capture_token: token, identity_phases: identityPhases, session, created_at: manifest.created_at });
console.log(`RECOVERY_CAPTURE_WAITING session=${session} capture_token=${token}`);

let ready, recorder, recorderClosed = false, recorderExit = null, captureError = '';
let behaviorStarted = false, preflightReady = false, phaseChanges = 0, previousPhase = -1;
let progressPending = '', rawPending = Buffer.alloc(0), framesEncoded = 0, secondsEncoded = 0;
let stage = 'waiting_for_ready', sourceBefore = {}, artifactBefore = {};
const probeWidth = 720, probeHeight = 450, frameBytes = probeWidth * probeHeight * 3;
const samples = [], markerPhases = new Set(), actionSceneHashes = new Set();
const probeLog = fs.createWriteStream(filename('capture-probes.jsonl'), { flags: 'wx' });
const progressTimer = setInterval(() => console.log(`RECOVERY_CAPTURE ${stage} encoded_seconds=${secondsEncoded.toFixed(1)} frames=${framesEncoded} probes=${samples.length}`), 10000);
progressTimer.unref();

function hashes(paths) {
  const output = {};
  const visit = relative => {
    const absolute = path.resolve(project, relative), checked = insideProject(absolute);
    if (!fs.existsSync(absolute)) return;
    if (fs.statSync(absolute).isDirectory()) {
      for (const item of fs.readdirSync(absolute).sort()) if (!['.git', '.godot', '__pycache__'].includes(item)) visit(path.join(relative, item));
    } else if (!/\.tmp$|\.pyc$|\.blend[12]$/i.test(relative)) output[checked] = sha(fs.readFileSync(absolute));
  };
  for (const relative of paths) visit(relative);
  return output;
}
const differences = (before, after) => Object.keys({ ...before, ...after }).filter(name => before[name] !== after[name]);
function pngChunk(type, data) {
  const name = Buffer.from(type), body = Buffer.concat([name, data]); let crc = 0xffffffff;
  for (const byte of body) { crc ^= byte; for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
  const output = Buffer.alloc(data.length + 12);
  output.writeUInt32BE(data.length); name.copy(output, 4); data.copy(output, 8); output.writeUInt32BE((crc ^ 0xffffffff) >>> 0, output.length - 4);
  return output;
}
function savePng(name, rgb) {
  const header = Buffer.alloc(13); header.writeUInt32BE(probeWidth); header.writeUInt32BE(probeHeight, 4); header[8] = 8; header[9] = 2;
  const rows = Buffer.alloc(probeHeight * (probeWidth * 3 + 1));
  for (let y = 0; y < probeHeight; y++) rgb.copy(rows, y * (probeWidth * 3 + 1) + 1, y * probeWidth * 3, (y + 1) * probeWidth * 3);
  fs.writeFileSync(filename(name), Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), pngChunk('IHDR', header), pngChunk('IDAT', deflateSync(rows)), pngChunk('IEND', Buffer.alloc(0))]));
}
function nearestColor(mean) {
  const distances = palette.map(color => Math.sqrt(color.reduce((sum, value, channel) => sum + (mean[channel] - value) ** 2, 0)));
  const nearest = Math.min(...distances); return nearest < 65 ? distances.indexOf(nearest) : -1;
}
function sampleCells(rgb, width, height, rect, cells, viewport = ready.viewport) {
  const output = [];
  for (let cell = 0; cell < cells; cell++) {
    const cx = (rect[0] + (cell + .5) * rect[2] / cells) * width / viewport[0], cy = (rect[1] + rect[3] / 2) * height / viewport[1];
    const mean = [0, 0, 0]; let pixels = 0;
    for (let y = Math.floor(cy) - 1; y <= Math.floor(cy) + 1; y++) for (let x = Math.floor(cx) - 1; x <= Math.floor(cx) + 1; x++) {
      if (x < 0 || y < 0 || x >= width || y >= height) continue;
      for (let channel = 0; channel < 3; channel++) mean[channel] += rgb[(y * width + x) * 3 + channel];
      pixels++;
    }
    output.push(pixels ? nearestColor(mean.map(value => value / pixels)) : -1);
  }
  return output;
}
function decodeCells(cells) {
  if (!cells.every(cell => cell >= 0)) return { valid: false, state: null, physics_frame: null };
  const tick = cells.slice(1).reduce((sum, value, index) => sum + value * 4 ** index, 0);
  const valid = tick <= Math.ceil((wallCap + 5) * ready.physics_hz) && (cells[0] !== 0 || tick === 0);
  return { valid, state: valid ? cells[0] : null, physics_frame: tick };
}
function analyze(rgb) {
  let sum = 0, squared = 0, pixels = 0; const colors = new Set();
  for (let y = 85; y < probeHeight - 35; y += 3) for (let x = 0; x < probeWidth; x += 3) {
    const offset = (y * probeWidth + x) * 3, r = rgb[offset], g = rgb[offset + 1], b = rgb[offset + 2];
    const luminance = .2126 * r + .7152 * g + .0722 * b;
    sum += luminance; squared += luminance * luminance; pixels++;
    colors.add(((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4));
  }
  const marker = sampleCells(rgb, probeWidth, probeHeight, ready.marker_rect, 1)[0];
  const identity = sampleCells(rgb, probeWidth, probeHeight, ready.identity_rect, 12);
  const counter = decodeCells(sampleCells(rgb, probeWidth, probeHeight, ready.frame_rect, 12));
  const identityValid = identity.every((value, index) => value === identityPhases[index]);
  const variance = Math.max(0, squared / Math.max(1, pixels) - (sum / Math.max(1, pixels)) ** 2);
  return { probe: samples.length, received_at: new Date().toISOString(), video_seconds_approximate: samples.length / 2,
    behavior_started: behaviorStarted, scene_variance: variance, quantized_colors: colors.size,
    marker_phase: marker, marker_identity_valid: identityValid, frame_marker: counter,
    scene_hash: sha(rgb.subarray(85 * probeWidth * 3, (probeHeight - 35) * probeWidth * 3)),
    content_valid: variance > 30 && colors.size >= 24 && marker >= 0 && identityValid && counter.valid };
}
function consume(rgb) {
  const sample = analyze(rgb); samples.push(sample); probeLog.write(JSON.stringify(sample) + '\n');
  if (behaviorStarted) { actionSceneHashes.add(sample.scene_hash); return; }
  savePng('preflight-latest.png', rgb);
  if (!sample.content_valid || sample.frame_marker.state !== 0 || sample.frame_marker.physics_frame !== 0) return;
  markerPhases.add(sample.marker_phase);
  if (previousPhase >= 0 && previousPhase !== sample.marker_phase) phaseChanges++;
  previousPhase = sample.marker_phase;
  if (!preflightReady && phaseChanges >= 2 && markerPhases.size >= 2) {
    preflightReady = true; savePng('preflight-game.png', rgb);
    write('preflight-ready.json', { capture_token: token, automatic_gate_passed: true, image: 'preflight-game.png',
      marker_phases: [...markerPhases], marker_changes: phaseChanges, latest_probe: sample, requires_actual_image_review: true,
      limit: 'Token, preview counter, variance and changing marker verify capture identity/readiness. They do not certify the quality of the pictured game.' });
    stage = 'waiting_for_owner_preflight_review';
    console.log(`RECOVERY_PREFLIGHT_READY image=${filename('preflight-game.png')} capture_token=${token}`);
  }
}
async function waitFor(predicate, seconds, description) {
  const started = performance.now();
  while (!predicate()) {
    if (captureError) throw Error(captureError);
    if (recorderClosed) throw Error(`Recorder exited ${recorderExit} before ${description}`);
    if (exists('runtime-fault.json')) throw Error(`Runtime fault: ${JSON.stringify(read('runtime-fault.json'))}`);
    if (exists('infrastructure-error.json')) throw Error(`Harness infrastructure failure: ${JSON.stringify(read('infrastructure-error.json'))}`);
    if (performance.now() - started > seconds * 1000) throw Error(`Timed out: ${description}`);
    await sleep(100);
  }
}
async function command(executable, args) {
  return await new Promise((resolve, reject) => {
    const child = spawn(executable, args, { cwd: project, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '', error = '';
    child.stdout.on('data', chunk => output += chunk); child.stderr.on('data', chunk => error += chunk);
    child.on('error', reject); child.on('close', code => code === 0 ? resolve(output) : reject(Error(`${executable} exited ${code}: ${error.slice(-1500)}`)));
  });
}
async function stopRecorder() {
  if (recorder && !recorderClosed) recorder.stdin.write('q\n');
  const started = performance.now();
  while (recorder && !recorderClosed && performance.now() - started < 15000) await sleep(100);
  if (recorder && !recorderClosed) { recorder.kill(); throw Error('Recorder did not flush within 15 seconds.'); }
}
function holdDiagnostics(frames) {
  const runs = []; let run = null;
  const finish = () => { if (run?.encoded_frames > 1) { run.observed_seconds = run.last_seconds - run.first_seconds; runs.push(run); } run = null; };
  for (const frame of frames) {
    if (!frame.valid || frame.state !== 1) { finish(); continue; }
    if (!run || run.physics_frame !== frame.physics_frame || frame.video_frame !== run.last_video_frame + 1) {
      finish(); run = { physics_frame: frame.physics_frame, first_seconds: frame.video_seconds, last_seconds: frame.video_seconds, last_video_frame: frame.video_frame, encoded_frames: 1 };
    } else { run.last_seconds = frame.video_seconds; run.last_video_frame = frame.video_frame; run.encoded_frames++; }
  }
  finish();
  return { repeated_counter_runs: runs, notable_holds: runs.filter(run => run.observed_seconds >= .1 - 1e-6),
    longest_observed_seconds: Math.max(0, ...runs.map(run => run.observed_seconds)), acceptance_gate: false,
    limit: 'Recorded repeated counters diagnose runtime/capture holds. They do not establish the cause.' };
}
async function decodeVideo(video, result) {
  const timestamps = JSON.parse(await command(options.ffprobe || 'ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_frames',
    '-show_entries', 'frame=best_effort_timestamp_time', '-of', 'json', filename('continuous.mp4')])).frames.map(frame => Number(frame.best_effort_timestamp_time));
  const stream = video.streams[0], sx = stream.width / ready.viewport[0], sy = stream.height / ready.viewport[1];
  const rect = ready.frame_rect, x = Math.floor(rect[0] * sx), y = Math.floor(rect[1] * sy);
  const width = Math.ceil((rect[0] + rect[2]) * sx) - x, height = Math.ceil((rect[1] + rect[3]) * sy) - y;
  const bytes = width * height * 3, localRect = [rect[0] * sx - x, rect[1] * sy - y, rect[2] * sx, rect[3] * sy];
  const decoded = []; let pending = Buffer.alloc(0);
  await new Promise((resolve, reject) => {
    const child = spawn(options.ffmpeg || 'ffmpeg', ['-hide_banner', '-loglevel', 'error', '-threads', '2', '-i', filename('continuous.mp4'),
      '-an', '-vf', `format=rgb24,crop=${width}:${height}:${x}:${y}`, '-c:v', 'rawvideo', '-threads', '1', '-pix_fmt', 'rgb24', '-fps_mode', 'passthrough', '-f', 'rawvideo', 'pipe:1'],
    { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let error = ''; child.stderr.on('data', chunk => error += chunk);
    child.stdout.on('data', chunk => {
      pending = Buffer.concat([pending, chunk]);
      while (pending.length >= bytes) {
        const rgb = pending.subarray(0, bytes); pending = pending.subarray(bytes);
        const marker = decodeCells(sampleCells(rgb, width, height, localRect, 12, [width, height]));
        const index = decoded.length;
        decoded.push({ video_frame: index, video_seconds: timestamps[index], ...marker,
          simulation_seconds: marker.physics_frame === null ? null : marker.physics_frame / ready.physics_hz });
      }
    });
    child.on('error', reject); child.on('close', code => code === 0 ? resolve() : reject(Error(`Frame marker decoder exited ${code}: ${error.slice(-1500)}`)));
  });
  const action = decoded.filter(frame => frame.valid && frame.state === 1), finished = decoded.filter(frame => frame.valid && frame.state === 2);
  let regressions = 0, indexGaps = 0;
  for (let index = 1; index < action.length; index++) {
    if (action[index].physics_frame < action[index - 1].physics_frame) regressions++;
    indexGaps += Math.max(0, action[index].video_frame - action[index - 1].video_frame - 1);
  }
  const holds = holdDiagnostics(decoded); write('action-counter-holds.json', holds);
  const first = action[0], last = action.at(-1), firstFinished = finished[0];
  const interval = first && last ? decoded.filter(frame => frame.video_frame >= first.video_frame && frame.video_frame <= last.video_frame) : [];
  const validRatio = decoded.filter(frame => frame.valid).length / Math.max(1, decoded.length);
  const wallSpan = first && last ? last.video_seconds - first.video_seconds : 0;
  const simulationSpan = first && last ? last.simulation_seconds - first.simulation_seconds : 0;
  const finalFrame = Number(result.physics_frames), tolerance = Math.ceil(ready.physics_hz / 30) + 2;
  const frameCoverage = Number.isSafeInteger(finalFrame) && finalFrame > 0 && first && last && firstFinished
    && first.physics_frame <= tolerance && Math.abs(last.physics_frame - finalFrame) <= tolerance && firstFinished.physics_frame === finalFrame;
  const alignment = { schema: 'based-football-recovery-video-alignment/v1', physics_hz: ready.physics_hz,
    method: 'Every encoded frame state/counter paired with its MP4 presentation timestamp. Coverage uses the actual finished match counter, never a fixed match duration.',
    valid_ratio: validRatio, required_valid_ratio: .95, decoded_frames: decoded.length, action_frames: action.length,
    finished_frames: finished.length, counter_regressions: regressions, action_video_index_gaps: indexGaps,
    invalid_frames_in_action_interval: interval.filter(frame => !frame.valid).length,
    other_states_in_action_interval: interval.filter(frame => frame.valid && frame.state !== 1).length,
    first_action: first ?? null, last_action: last ?? null, first_finished: firstFinished ?? null,
    actual_final_physics_frame: Number.isSafeInteger(finalFrame) ? finalFrame : null, frame_coverage_tolerance_ticks: tolerance,
    actual_sequence_frame_coverage: Boolean(frameCoverage), wall_span_seconds: wallSpan, simulation_span_seconds: simulationSpan,
    simulation_wall_ratio: wallSpan > 0 ? simulationSpan / wallSpan : null,
    usable: validRatio >= .95 && regressions === 0 && indexGaps === 0 && action.length > 100 && finished.length > 0
      && decoded.length === timestamps.length && timestamps.every(Number.isFinite) && Boolean(frameCoverage),
    counter_holds: { file: 'action-counter-holds.json', notable_holds: holds.notable_holds.length, longest_observed_seconds: holds.longest_observed_seconds }, frames: decoded };
  write('video-frame-alignment.json', alignment);
  return alignment;
}

try {
  await waitFor(() => exists('ready.json'), 300, 'recovery scene readiness'); ready = read('ready.json');
  if (ready.game_ready !== true || ready.scene !== 'recovery_full_match' || ready.capture_token !== token || !/^[1-9]\d*$/.test(String(ready.hwnd))) throw Error('Game readiness, scene, token or native window identity mismatch.');
  if (!Array.isArray(ready.viewport) || ready.viewport[0] !== 1280 || ready.viewport[1] !== 800) throw Error('Expected settled 1280x800 viewport.');
  if (JSON.stringify(ready.identity_phases) !== JSON.stringify(identityPhases)) throw Error('Scene identity strip differs from the fresh request.');
  ready.marker_rect ??= [1120, 22, 100, 28]; ready.identity_rect ??= [1120, 58, 96, 12]; ready.frame_rect ??= [1120, 82, 96, 12]; ready.physics_hz ??= 120;
  const packPath = path.resolve(project, options.pack || ready.pack_path || 'build/BasedFootball.pck');
  const executablePath = path.resolve(project, options.executable || ready.executable_path || 'build/BasedFootball.exe');
  const artifactPaths = [insideProject(packPath), insideProject(executablePath)];
  for (const relative of artifactPaths) if (!fs.statSync(path.join(project, relative)).isFile()) throw Error(`Build artifact missing: ${relative}`);
  await waitFor(() => exists('window-ready.json'), 180, 'verified native client geometry');
  const settledWindow = read('window-ready.json');
  if (settledWindow.capture_token !== token || settledWindow.client_width !== 1280 || settledWindow.client_height !== 800) throw Error('Native client geometry was not verified for this capture.');
  sourceBefore = hashes(sourcePaths); artifactBefore = hashes(artifactPaths);
  manifest.runtime = ready; manifest.source_paths = sourcePaths; manifest.source_hashes = sourceBefore;
  manifest.artifact_paths = artifactPaths; manifest.artifact_hashes = artifactBefore; write('manifest.json', manifest);
  stage = 'recording_preflight';
  const source = `gfxcapture=hwnd=${ready.hwnd}:capture_cursor=0:capture_border=0:display_border=0:max_framerate=30:output_fmt=bgra,hwdownload,format=bgra`;
  const graph = `[0:v]split=2[video][probe];[video]fps=30,format=yuv420p[vout];[probe]fps=2,scale=${probeWidth}:${probeHeight},format=rgb24[pout]`;
  recorder = spawn(options.ffmpeg || 'ffmpeg', ['-hide_banner', '-y', '-loglevel', 'warning', '-stats_period', '0.1', '-progress', 'pipe:1',
    '-f', 'lavfi', '-i', source, '-filter_complex', graph, '-map', '[vout]', '-an', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '20',
    '-threads', '2', '-g', '30', '-movflags', '+faststart', filename('continuous.mp4'), '-map', '[pout]', '-an', '-c:v', 'rawvideo',
    '-threads', '1', '-pix_fmt', 'rgb24', '-fps_mode', 'passthrough', '-f', 'rawvideo', 'pipe:3'],
  { cwd: project, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe', 'pipe'] });
  recorder.stderr.pipe(fs.createWriteStream(filename('ffmpeg.log'), { flags: 'wx' }));
  recorder.stdin.on('error', error => { if (!recorderClosed) captureError ||= `Recorder input: ${error.message}`; });
  recorder.on('error', error => { captureError = `Recorder launch: ${error.message}`; recorderClosed = true; });
  recorder.on('close', code => { recorderClosed = true; recorderExit = code; });
  recorder.stdout.on('data', chunk => {
    progressPending += chunk.toString(); let end;
    while ((end = progressPending.indexOf('\n')) >= 0) {
      const line = progressPending.slice(0, end).trim(); progressPending = progressPending.slice(end + 1);
      if (line.startsWith('frame=')) framesEncoded = Number(line.slice(6));
      if (line.startsWith('out_time_us=')) secondsEncoded = Number(line.slice(12)) / 1e6;
    }
  });
  recorder.stdio[3].on('data', chunk => {
    rawPending = rawPending.length ? Buffer.concat([rawPending, chunk]) : chunk;
    while (rawPending.length >= frameBytes) {
      const rgb = rawPending.subarray(0, frameBytes); rawPending = rawPending.subarray(frameBytes);
      try { consume(rgb); } catch (error) { captureError = `Capture probe: ${error.message}`; }
    }
  });
  await waitFor(() => preflightReady && framesEncoded > 0, 45, 'same-stream nonblank preflight, identity and preview counter');
  await waitFor(() => exists('preflight-verified.flag'), 300, 'owner inspection of actual preflight image');
  const ownerReview = read('preflight-verified.flag');
  if (ownerReview.capture_token !== token || ownerReview.game_visible !== true) throw Error('Owner preflight acknowledgment must identify this token and game_visible:true.');
  manifest.recording.preflight_verified = true; manifest.recording.owner_review = ownerReview;
  manifest.recording.release_video_seconds_approximate = secondsEncoded;
  manifest.source_changes_before_start = differences(sourceBefore, hashes(sourcePaths));
  manifest.artifact_changes_before_start = differences(artifactBefore, hashes(artifactPaths));
  if (manifest.source_changes_before_start.length || manifest.artifact_changes_before_start.length) throw Error('Source or built artifacts changed after readiness; refusing to release start.');
  manifest.start_flag_released_at = new Date().toISOString(); write('manifest.json', manifest);
  behaviorStarted = true; stage = 'running_full_match'; write('start.flag', { capture_token: token });
  await waitFor(() => exists('started.json'), 10, 'match start acknowledgment');
  const started = read('started.json'); if (started.capture_token !== token) throw Error('Started token mismatch.');
  manifest.started = started; write('manifest.json', manifest);
  console.log('RECOVERY_MATCH_RUNNING');
  await waitFor(() => exists('finished.json'), wallCap, 'the single full match');
  const finished = read('finished.json'); if (finished.capture_token !== token) throw Error('Finished token mismatch.');
  await waitFor(() => exists('result.json'), 5, 'preserved match result');
  const result = read('result.json'); if (result.capture_token && result.capture_token !== token) throw Error('Result token mismatch.');
  stage = 'flushing_recording'; await sleep(900); await stopRecorder();
  if (recorderExit !== 0) throw Error(`Recorder exited ${recorderExit}`);
  write('allowexit.flag', { capture_token: token, reason: 'WGC recording flushed', flushed_at: new Date().toISOString() });
  stage = 'offline_evidence_analysis';
  const video = JSON.parse(await command(options.ffprobe || 'ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries',
    'format=duration,size:stream=codec_name,width,height,nb_frames,r_frame_rate', '-of', 'json', filename('continuous.mp4')]));
  const alignment = await decodeVideo(video, result);
  const actionProbes = samples.filter(sample => sample.behavior_started), validProbes = actionProbes.filter(sample => sample.content_valid);
  const validProbeRatio = validProbes.length / Math.max(1, actionProbes.length);
  const sourceAfter = hashes(sourcePaths), artifactAfter = hashes(artifactPaths);
  manifest.source_changes_during_run = differences(sourceBefore, sourceAfter);
  manifest.artifact_changes_during_run = differences(artifactBefore, artifactAfter);
  manifest.source_freeze_passed = !manifest.source_changes_during_run.length && !manifest.artifact_changes_during_run.length;
  const capture = { schema: 'based-football-recovery-capture-review/v1', method: manifest.recording.method, video,
    preflight_verified: true, action_probes: actionProbes.length, valid_content_ratio: validProbeRatio,
    distinct_action_scene_hashes: actionSceneHashes.size, frame_alignment: { ...alignment, frames: undefined },
    capture_usable: alignment.usable && validProbeRatio >= .95 && actionSceneHashes.size > 20,
    match_full_time_reported_by_fixture: result.match_full_time === true,
    visual_verdict: 'Pending actual uninterrupted footage review. Capture success and a full-time event do not establish good football quality.' };
  write('capture-review.json', capture);
  manifest.finished_at = new Date().toISOString(); manifest.recording.encoded_frames = framesEncoded;
  manifest.recording.frame_alignment_file = 'video-frame-alignment.json'; manifest.scene_result_file = 'result.json';
  manifest.scene_result = result; manifest.capture_result = capture.capture_usable ? 'usable' : 'failed';
  manifest.match_full_time_reported_by_fixture = result.match_full_time === true;
  manifest.fixture_reported_pass = result.pass === true;
  manifest.status = !capture.capture_usable || !manifest.source_freeze_passed ? 'capture_or_source_freeze_failed'
    : result.pass !== true || result.match_full_time !== true ? 'capture_complete_fixture_failed' : 'capture_complete_actual_match_review_required';
  write('manifest.json', manifest); stage = 'completed';
  console.log(`RECOVERY_CAPTURE_DONE status=${manifest.status} full_time=${result.match_full_time === true} fixture_pass=${result.pass === true} video=${filename('continuous.mp4')}`);
  if (!capture.capture_usable || !manifest.source_freeze_passed || result.match_full_time !== true || result.pass !== true) process.exitCode = 1;
} catch (error) {
  write('capture-error.json', { error: error.message, stage, behavior_started: behaviorStarted, recorder_exit: recorderExit,
    probe_count: samples.length, last_probe: samples.at(-1) ?? null, created_at: new Date().toISOString() });
  console.error(error.message); process.exitCode = 1;
} finally {
  clearInterval(progressTimer);
  try { await stopRecorder(); } catch (error) { console.error(error.message); }
  await new Promise(resolve => probeLog.end(resolve));
  console.log('Recovery recorder stopped. It never launches or kills Godot.');
}
