// The game owns scene truth; game-dev owns execution records and sealed hashes.
import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const engine = 'C:\\Program Files\\Godot\\Godot_v4.6.1-stable_mono_win64\\Godot_v4.6.1-stable_mono_win64_console.exe';
const pack = path.join(project, 'build', 'BasedFootball.pck');
const decisionMatch = process.argv[2] === 'decisions';
const impacts = process.argv[2] === 'impacts';
const athletes = process.argv[2] === 'athletes';
const skinnedShot = process.argv[2] === 'skinned-shot';
const shotsTeam = process.argv[2] === 'shots-team';
const humanMotion = process.argv[2] === 'human-motion';
const teamplay = process.argv[2] === 'teamplay';
const rendered = teamplay || humanMotion || shotsTeam || skinnedShot || athletes || impacts || decisionMatch || process.argv[2] === 'rendered';
const runDir = process.env.GAME_DEV_RUN_DIR;
if (!runDir || !process.env.GAME_DEV_RUN_ID) throw new Error('Run through the game-dev scenario harness.');
await access(engine);
await access(pack);
const staging = path.join(runDir, 'staging');
await mkdir(staging, { recursive: true });
// The harness deliberately narrows inherited variables. Godot's Windows user://
// resolver requires APPDATA; restore only the current user's known app-data roots.
const userHome = homedir();
const result = await new Promise((resolve, reject) => {
  const displayArgs = rendered ? ['--windowed', '--position', '30000,30000', '--resolution', '960x600', '--audio-driver', 'Dummy'] : ['--headless'];
  const child = spawn(engine, [...displayArgs, '--path', path.join(project, 'build'),
    '--main-pack', pack, '--log-file', path.join(staging, 'godot.log'), '--', teamplay ? '--teamplay-acceptance' : humanMotion ? '--human-motion-acceptance' : shotsTeam ? '--shots-team-acceptance' : skinnedShot ? '--skinned-shot-acceptance' : athletes ? '--athlete-acceptance' : impacts ? '--impact-acceptance' : decisionMatch ? '--decision-acceptance' : rendered ? '--handling-acceptance' : '--visual-acceptance'], {
    cwd: project, windowsHide: true,
    env: { ...process.env, APPDATA: path.join(userHome, 'AppData', 'Roaming'),
      LOCALAPPDATA: path.join(userHome, 'AppData', 'Local'), BASED_FOOTBALL_EVIDENCE: staging },
    stdio: ['ignore', 'inherit', 'inherit'],
  });
  child.once('error', reject);
  child.once('close', (code, signal) => resolve({ code, signal }));
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
  attributes: { passed, measured_by: 'engine_counter', pixel_evidence: false },
}));
await writeFile(path.join(staging, 'checks.jsonl'), telemetry.map(x => JSON.stringify(x)).join('\n') + '\n');
const manifest = {
  schema: 'game_dev.capture.v1', runId: process.env.GAME_DEV_RUN_ID,
  adapterId: process.env.GAME_DEV_ADAPTER_ID, scenarioId: process.env.GAME_DEV_SCENARIO_ID,
  sourceFormat: 'game-dev-capture-v1', frames: (report.screenshots ?? []).map((name, index) => ({
    index, label: name.replace(/\.png$/, '').toLowerCase(), attachments: [{ kind: 'color', path: `staging/${name}`, encoding: 'png' }],
  })), telemetry: ['staging/checks.jsonl'],
  profiles: ['staging/scene-report.json', 'staging/godot.log'],
  adapterEvidence: { windowless: !rendered, gpuExecutionReported: rendered,
    gpuCompletionIdentityReported: false, hardwarePerformanceReported: false,
    pixelVisualInspectionPerformed: false,
    notes: [decisionMatch ? 'Bounded reactive controller decisions through production actions. Normal match AI and rules are active; hardware input is disabled. No hardware timing claim.' : rendered ? 'Bounded production-physics handling sequence with rendered frames. Hardware input and autonomous match AI are disabled. No hardware timing claim.' : 'Godot headless uses the dummy renderer. This is scene/resource integrity evidence, not rendered appearance or gameplay verification.'] },
};
await writeFile(process.env.GAME_DEV_CAPTURE_MANIFEST ?? path.join(staging, 'capture.json'), JSON.stringify(manifest, null, 2));
console.log(`SCENE_CHECK_RESULT: ${report.pass ? 'PASS' : 'FAIL'}; ${Object.keys(report.checks).length} checks; rendered=${rendered}.`);
if (result.code !== 0 || !report.pass) process.exitCode = 1;
