import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, access, copyFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = 'C:\\Program Files\\Godot\\Godot_v4.6.1-stable_mono_win64\\Godot_v4.6.1-stable_mono_win64_console.exe';
const build = path.join(project, 'build', 'candidate');
const pack = path.join(build, 'BasedFootball.pck');
const runDir = process.env.GAME_DEV_RUN_DIR;
if (!runDir || !process.env.GAME_DEV_RUN_ID) throw new Error('Run through the game-dev scenario harness.');
await access(engine);
await access(pack);
const staging = path.join(runDir, 'staging');
await mkdir(staging, { recursive: true });
const userHome = homedir();
const result = await new Promise((resolve, reject) => {
  const child = spawn(engine, ['--windowed', '--position', '30000,30000', '--resolution', '960x600', '--audio-driver', 'Dummy',
    '--path', build, '--main-pack', pack, '--log-file', path.join(staging, 'godot.log'), '--', '--natural-character-acceptance'], {
    cwd: project, windowsHide: true,
    env: { ...process.env, APPDATA: path.join(userHome, 'AppData', 'Roaming'),
      LOCALAPPDATA: path.join(userHome, 'AppData', 'Local'), BASED_FOOTBALL_EVIDENCE: staging },
    stdio: ['ignore', 'inherit', 'inherit'],
  });
  const watchdog = setTimeout(() => child.kill(), 170_000);
  child.once('error', reject);
  child.once('close', (code, signal) => { clearTimeout(watchdog); resolve({ code, signal }); });
  const stop = () => child.kill();
  process.once('SIGTERM', stop);
  child.once('close', () => process.removeListener('SIGTERM', stop));
});
const log = await readFile(path.join(staging, 'godot.log'), 'utf8');
if (/SCRIPT ERROR:|^ERROR:/m.test(log)) throw new Error('Godot reported a runtime error; see godot.log.');
const report = JSON.parse(await readFile(path.join(staging, 'scene-report.json'), 'utf8'));
const telemetry = Object.entries(report.checks).map(([name, passed], sequence) => ({
  schema: 'game_dev.telemetry.v1', runId: process.env.GAME_DEV_RUN_ID,
  sequence, timestampNs: String(sequence), category: 'diagnostic', name,
  attributes: { passed, measured_by: 'production_loop_observer', pixel_evidence: false },
}));
await writeFile(path.join(staging, 'checks.jsonl'), telemetry.map(x => JSON.stringify(x)).join('\n') + '\n');

// Packaging reads the previous passing run; it never launches a baseline game.
const baselineDir = path.join(project, 'evidence', 'game-dev', '.game-dev', 'runs', report.baseline_run, 'staging');
const baselineComparison = { baselineRun: report.baseline_run, baselineReexecuted: false,
  baselinePassed: false, baselineFrames: [], candidateFrames: [],
  notes: ['Original passing foundation frames are retained as visual references. Camera angles and action timing differ; these are human comparison evidence, not a pixel-equality regression.'] };
const baselineFrames = [];
try {
  const baselineReport = JSON.parse(await readFile(path.join(baselineDir, 'scene-report.json'), 'utf8'));
  baselineComparison.baselinePassed = baselineReport.pass === true;
  for (const activity of ['walk', 'jog', 'sprint', 'turn_stop', 'dribble_jog', 'dribble_sprint']) {
    const source = `${activity}_end.png`;
    const name = `baseline_${activity}.png`;
    await copyFile(path.join(baselineDir, source), path.join(staging, name));
    baselineFrames.push(name);
    baselineComparison.baselineFrames.push({ activity, filename: name, source });
  }
  baselineComparison.candidateFrames = report.screenshots.filter(name => name.startsWith('athlete_0_'));
  try {
    await copyFile(path.join(baselineDir, 'foundation-motion.mp4'), path.join(staging, 'baseline-foundation-motion.mp4'));
    baselineComparison.baselineMotionVideo = 'staging/baseline-foundation-motion.mp4';
  } catch (error) {
    baselineComparison.notes.push(`Baseline video unavailable; original still references preserved: ${error.message}`);
  }
} catch (error) {
  baselineComparison.notes.push(`Original baseline reference unavailable: ${error.message}`);
}
await writeFile(path.join(staging, 'baseline-comparison.json'), JSON.stringify(baselineComparison, null, 2));

let motionVideo = null;
if (report.motion_frames?.length) {
  const videoResult = await new Promise(resolve => {
    const encoder = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-framerate', '10', '-i', path.join(staging, 'character_%04d.png'),
      '-c:v', 'libx264', '-threads', '2', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-y', path.join(staging, 'natural-characters.mp4')], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    encoder.stderr.on('data', data => { stderr += data; });
    encoder.once('error', error => resolve({ code: null, error: error.message }));
    encoder.once('close', code => resolve({ code, error: stderr }));
  });
  if (videoResult.code === 0) motionVideo = 'staging/natural-characters.mp4';
  else await writeFile(path.join(staging, 'video-encoding.txt'), videoResult.error || 'Video encoder unavailable; original PNG sequence preserved.');
}
const manifest = {
  schema: 'game_dev.capture.v1', runId: process.env.GAME_DEV_RUN_ID,
  adapterId: process.env.GAME_DEV_ADAPTER_ID, scenarioId: process.env.GAME_DEV_SCENARIO_ID,
  sourceFormat: 'game-dev-capture-v1', frames: [...(report.screenshots ?? []), ...baselineFrames].map((name, index) => ({
    index, label: name.replace(/\.png$/, '').toLowerCase(), attachments: [{ kind: 'color', path: `staging/${name}`, encoding: 'png' }],
  })), telemetry: ['staging/checks.jsonl'],
  profiles: ['staging/scene-report.json', 'staging/godot.log', 'staging/character-trace.json', 'staging/baseline-comparison.json'],
  adapterEvidence: { windowless: false, gpuExecutionReported: true,
    gpuCompletionIdentityReported: false, hardwarePerformanceReported: false,
    pixelVisualInspectionPerformed: false,
    notes: ['One off-screen production-loop execution across six athletes. Normal match/referee/physics remain active; the other five bodies are parked at scenario setup. Front/profile/angled rendered sequences and planted ankle/pose traces support human review, without a subjective-naturalness claim.', ...(motionVideo ? [`Continuous visual evidence: ${motionVideo}`] : []), 'Baseline comparison reads the already completed passing foundation run; no baseline rerun.'] },
};
await writeFile(process.env.GAME_DEV_CAPTURE_MANIFEST ?? path.join(staging, 'capture.json'), JSON.stringify(manifest, null, 2));
console.log(`SCENE_CHECK_RESULT: ${report.pass ? 'PASS' : 'FAIL'}; ${Object.keys(report.checks).length} checks; six-athlete rendered production-loop sequence.`);
if (result.code !== 0 || !report.pass) process.exitCode = 1;
