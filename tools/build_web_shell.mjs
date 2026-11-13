// Refresh the checked-in shell after --export-pack when matching Web runtime
// files already exist. A full Godot Web export applies these same placeholders.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const build = path.join(root, 'web_build');
const previous = fs.readFileSync(path.join(build, 'index.html'), 'utf8');
const config = JSON.parse(previous.match(/const GODOT_CONFIG = (\{[^\n]+\});/)[1]);
for (const file of Object.keys(config.fileSizes)) config.fileSizes[file] = fs.statSync(path.join(build, file)).size;
const values = {
 GODOT_PROJECT_NAME: 'Gridiron', GODOT_HEAD_INCLUDE: '<link rel="icon" href="index.icon.png">',
 GODOT_URL: 'index.js', GODOT_CONFIG: JSON.stringify(config), GODOT_THREADS_ENABLED: 'false',
};
const shell = fs.readFileSync(path.join(root, 'assets/ui/web_shell.html'), 'utf8')
 .replace(/\$GODOT_[A-Z_]+/g, key => {
  const value = values[key.slice(1)];
  if (value === undefined) throw new Error('Unknown shell placeholder: ' + key);
  return value;
 });
fs.writeFileSync(path.join(build, 'index.html'), shell);
fs.copyFileSync(path.join(root, 'assets/fonts/Oswald.ttf'), path.join(build, 'loader-font.ttf'));
fs.copyFileSync(path.join(root, 'assets/ui/loading_turf.svg'), path.join(build, 'loader-turf.svg'));
fs.copyFileSync(path.join(root, 'assets/ui/boot_splash.png'), path.join(build, 'index.png'));
for (const skin of ['light', 'dark']) fs.copyFileSync(path.join(root, `assets/hands/hand_${skin}.png`), path.join(build, `loader-hand-${skin}.png`));
console.log('Gridiron Web shell refreshed; PCK bytes:', config.fileSizes['index.pck']);
