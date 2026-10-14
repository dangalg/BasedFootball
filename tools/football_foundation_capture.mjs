// One production-loop game execution; the harness seals the reports and pixels.
import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, access } from 'node:fs/promises';
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
    '--path', build, '--main-pack', pack, '--log-file', path.join(staging, 'godot.log'), '--', '--foundation-acceptance'], {
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
// Encoding the already recorded frames is evidence packaging, not another run.
let motionVideo = null;
if (report.motion_frames?.length) {
  const videoResult = await new Promise(resolve => {
    const encoder = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-framerate', '10', '-i', path.join(staging, 'motion_%04d.png'),
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-y', path.join(staging, 'foundation-motion.mp4')], { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    encoder.stderr.on('data', data => { stderr += data; });
    encoder.once('error', error => resolve({ code: null, error: error.message }));
    encoder.once('close', code => resolve({ code, error: stderr }));
  });
  if (videoResult.code === 0) motionVideo = 'staging/foundation-motion.mp4';
  else await writeFile(path.join(staging, 'video-encoding.txt'), videoResult.error || 'Video encoder unavailable; original PNG sequence preserved.');
}
const manifest = {
  schema: 'game_dev.capture.v1', runId: process.env.GAME_DEV_RUN_ID,
  adapterId: process.env.GAME_DEV_ADAPTER_ID, scenarioId: process.env.GAME_DEV_SCENARIO_ID,
  sourceFormat: 'game-dev-capture-v1', frames: (report.screenshots ?? []).map((name, index) => ({
    index, label: name.replace(/\.png$/, '').toLowerCase(), attachments: [{ kind: 'color', path: `staging/${name}`, encoding: 'png' }],
  })), telemetry: ['staging/checks.jsonl'],
  profiles: ['staging/scene-report.json', 'staging/godot.log', 'staging/foundation-trace.json'],
  adapterEvidence: { windowless: false, gpuExecutionReported: true,
    gpuCompletionIdentityReported: false, hardwarePerformanceReported: false,
    pixelVisualInspectionPerformed: false,
    notes: ['One off-screen rendered production-match execution with controller decisions, normal AI/referee/physics and continuous motion frames. Only scenario setups reposition bodies. No hardware input, subjective-feel or hardware-performance claim.', ...(motionVideo ? [`Continuous movement evidence: ${motionVideo}`] : [])] },
};
await writeFile(process.env.GAME_DEV_CAPTURE_MANIFEST ?? path.join(staging, 'capture.json'), JSON.stringify(manifest, null, 2));
console.log(`SCENE_CHECK_RESULT: ${report.pass ? 'PASS' : 'FAIL'}; ${Object.keys(report.checks).length} checks; one rendered production-loop sequence.`);
if (result.code !== 0 || !report.pass) process.exitCode = 1;
