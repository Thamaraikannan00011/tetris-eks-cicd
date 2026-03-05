const canvas  = document.getElementById('gameCanvas');
const ctx     = canvas.getContext('2d');
const nCanvas = document.getElementById('nextCanvas');
const nCtx    = nCanvas.getContext('2d');

const COLS = 10, ROWS = 20, CELL = 30;

const COLORS = {
  I:'#00aacc', O:'#ddaa00', T:'#9922bb',
  S:'#22aa44', Z:'#dd2233', J:'#2255cc', L:'#dd6600',
  FLASH:'#ffffff'
};

const PIECES = {
  I:{ shape:[[0,0,0,0],[1,1,1,1],[0,0,0,0],[0,0,0,0]], color:'I' },
  O:{ shape:[[1,1],[1,1]],                              color:'O' },
  T:{ shape:[[0,1,0],[1,1,1],[0,0,0]],                 color:'T' },
  S:{ shape:[[0,1,1],[1,1,0],[0,0,0]],                 color:'S' },
  Z:{ shape:[[1,1,0],[0,1,1],[0,0,0]],                 color:'Z' },
  J:{ shape:[[1,0,0],[1,1,1],[0,0,0]],                 color:'J' },
  L:{ shape:[[0,0,1],[1,1,1],[0,0,0]],                 color:'L' },
};
const PIECE_KEYS = Object.keys(PIECES);

// ── State ──
let board, current, next, score, lines, level;
let highScore = parseInt(localStorage.getItem('tetris_hi') || '0');
let gameOver  = true;
let userPaused = false;   // only true when player pressed P
let clearing  = false;    // true while flash animation runs
let animId, dropAcc = 0, dropInterval = 800;
let lastTime  = 0;
let pieceCounts = {};
let bag = [];

// ── Board ──
function createBoard() {
  return Array.from({length: ROWS}, () => Array(COLS).fill(null));
}

// ── Piece bag ──
function getNextPiece() {
  if (!bag.length) bag = [...PIECE_KEYS].sort(() => Math.random() - 0.5);
  const key = bag.pop();
  const p = PIECES[key];
  return {
    shape: p.shape.map(r => [...r]),
    color: p.color,
    x: Math.floor((COLS - p.shape[0].length) / 2),
    y: 0
  };
}

// ── Start / Restart ──
function startGame() {
  document.getElementById('overlay').classList.add('hidden');
  board        = createBoard();
  score        = 0; lines = 0; level = 1;
  dropInterval = 800;
  dropAcc      = 0;
  pieceCounts  = {};
  PIECE_KEYS.forEach(k => pieceCounts[k] = 0);
  gameOver     = false;
  userPaused   = false;
  clearing     = false;
  bag          = [];
  next         = getNextPiece();
  spawnPiece();
  updateHUD();
  cancelAnimationFrame(animId);
  lastTime = 0;
  animId = requestAnimationFrame(loop);
}

// ── Spawn ──
function spawnPiece() {
  current = next;
  next    = getNextPiece();
  pieceCounts[current.color] = (pieceCounts[current.color] || 0) + 1;
  if (collides(current, 0, 0)) endGame();
}

// ── Main loop ──
function loop(ts) {
  const dt = lastTime ? ts - lastTime : 0;
  lastTime = ts;

  // Only auto-drop when truly playing
  if (!gameOver && !userPaused && !clearing && current) {
    dropAcc += dt;
    if (dropAcc >= dropInterval) {
      dropAcc = 0;
      tryDrop();
    }
  }

  draw();
  animId = requestAnimationFrame(loop);
}

// ── Auto-drop one row ──
function tryDrop() {
  if (!current) return;
  if (!collides(current, 0, 1)) {
    current.y++;
  } else {
    lockPiece();
  }
}

// ── Collision ──
function collides(piece, dx, dy, shape) {
  shape = shape || piece.shape;
  for (let r = 0; r < shape.length; r++) {
    for (let c = 0; c < shape[r].length; c++) {
      if (!shape[r][c]) continue;
      const nr = piece.y + r + dy;
      const nc = piece.x + c + dx;
      if (nc < 0 || nc >= COLS || nr >= ROWS) return true;
      if (nr >= 0 && board[nr][nc]) return true;
    }
  }
  return false;
}

// ── Player moves ──
function moveLeft()  { if (current && !clearing) { if (!collides(current,-1,0)) current.x--; } }
function moveRight() { if (current && !clearing) { if (!collides(current, 1,0)) current.x++; } }

function softDrop() {
  if (!current || clearing) return;
  if (!collides(current, 0, 1)) { current.y++; score++; updateHUD(); }
  else lockPiece();
  dropAcc = 0;
}

function hardDrop() {
  if (!current || clearing) return;
  let dropped = 0;
  while (!collides(current, 0, 1)) { current.y++; dropped++; }
  score += dropped * 2;
  lockPiece();
  dropAcc = 0;
}

function rotate() {
  if (!current || clearing) return;
  const rot = current.shape[0].map((_, ci) =>
    current.shape.map(row => row[ci]).reverse()
  );
  const kicks = [0, -1, 1, -2, 2];
  for (const k of kicks) {
    if (!collides(current, k, 0, rot)) {
      current.shape = rot;
      current.x += k;
      return;
    }
  }
}

// ── Lock piece onto board ──
function lockPiece() {
  if (!current) return;

  // Stamp onto board
  current.shape.forEach((row, r) => {
    row.forEach((val, c) => {
      if (val && current.y + r >= 0)
        board[current.y + r][current.x + c] = current.color;
    });
  });
  current = null;

  // Find full rows
  const fullRows = [];
  for (let r = 0; r < ROWS; r++) {
    if (board[r].every(cell => cell !== null)) fullRows.push(r);
  }

  if (fullRows.length === 0) {
    // No lines — spawn immediately
    spawnPiece();
    updateHUD();
    return;
  }

  // Animate then clear
  clearing = true;
  let tick = 0;
  const iv = setInterval(() => {
    // Toggle rows between FLASH and original
    fullRows.forEach(r => {
      board[r] = board[r].map(cell =>
        cell === 'FLASH' ? 'CLEAR' : 'FLASH'
      );
    });
    tick++;
    if (tick >= 6) {
      clearInterval(iv);

      // Remove the cleared rows (scan bottom-up, stable)
      for (let i = ROWS - 1; i >= 0; i--) {
        if (board[i].every(cell => cell === 'FLASH' || cell === 'CLEAR' || cell === null)) {
          if (board[i].some(cell => cell === 'FLASH' || cell === 'CLEAR')) {
            board.splice(i, 1);
            board.unshift(Array(COLS).fill(null));
          }
        }
      }

      // Score
      const cleared = fullRows.length;
      const pts = [0, 100, 300, 500, 800];
      score += (pts[cleared] || 800) * level;
      lines += cleared;
      level  = Math.min(10, Math.floor(lines / 10) + 1);
      dropInterval = Math.max(80, 800 - (level - 1) * 80);
      if (score > highScore) {
        highScore = score;
        localStorage.setItem('tetris_hi', highScore);
      }

      clearing = false;
      dropAcc  = 0;
      spawnPiece();
      updateHUD();
    }
  }, 70);
}

// ── Game Over ──
function endGame() {
  gameOver = true;
  if (score > highScore) {
    highScore = score;
    localStorage.setItem('tetris_hi', highScore);
  }
  document.getElementById('ovTitle').textContent = 'GAME OVER';
  document.getElementById('ovSub').textContent   = 'SCORE';
  document.getElementById('ovScore').textContent = score.toLocaleString();
  document.getElementById('ovBtn').textContent   = '▶ RETRY';
  document.getElementById('ovBtn').onclick = startGame;
  document.getElementById('overlay').classList.remove('hidden');
}

// ── Pause (P key only) ──
function togglePause() {
  if (gameOver || clearing) return;
  userPaused = !userPaused;
  if (userPaused) {
    document.getElementById('ovTitle').textContent = 'PAUSED';
    document.getElementById('ovSub').textContent   = 'PRESS P TO RESUME';
    document.getElementById('ovScore').textContent = '';
    document.getElementById('ovBtn').textContent   = '▶ RESUME';
    document.getElementById('ovBtn').onclick = togglePause;
    document.getElementById('overlay').classList.remove('hidden');
  } else {
    document.getElementById('overlay').classList.add('hidden');
    dropAcc  = 0;
    lastTime = 0;
  }
}

// ── Draw board ──
function draw() {
  // White background
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  // Faint grid
  ctx.strokeStyle = 'rgba(180,185,210,0.55)';
  ctx.lineWidth = 0.5;
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++)
      ctx.strokeRect(c * CELL, r * CELL, CELL, CELL);

  // Board cells
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const cell = board[r][c];
      if (!cell) continue;
      if (cell === 'FLASH') {
        // White flash
        ctx.fillStyle = '#ffe066';
        ctx.fillRect(c*CELL+1, r*CELL+1, CELL-2, CELL-2);
      } else if (cell === 'CLEAR') {
        // Empty flash frame
        ctx.fillStyle = '#f0f0f0';
        ctx.fillRect(c*CELL+1, r*CELL+1, CELL-2, CELL-2);
      } else {
        drawCell(ctx, c, r, cell);
      }
    }
  }

  // Ghost piece
  if (current && !gameOver && !clearing) {
    let gy = current.y;
    while (!collides(current, 0, gy - current.y + 1)) gy++;
    current.shape.forEach((row, r) =>
      row.forEach((val, c) => {
        if (val) drawGhost(ctx, current.x + c, gy + r, current.color);
      })
    );
    // Active piece
    current.shape.forEach((row, r) =>
      row.forEach((val, c) => {
        if (val && current.y + r >= 0)
          drawCell(ctx, current.x + c, current.y + r, current.color);
      })
    );
  }

  drawNext();
}

function drawCell(ctx, c, r, colorKey) {
  const x = c * CELL, y = r * CELL;
  const col = COLORS[colorKey] || '#888888';
  // Tinted bg
  ctx.fillStyle = col + '28';
  ctx.fillRect(x+1, y+1, CELL-2, CELL-2);
  // Solid inner block
  ctx.fillStyle = col;
  ctx.fillRect(x+5, y+5, CELL-10, CELL-10);
  // Border
  ctx.strokeStyle = col;
  ctx.lineWidth = 2;
  ctx.strokeRect(x+1.5, y+1.5, CELL-3, CELL-3);
  // Shine
  ctx.fillStyle = 'rgba(255,255,255,0.5)';
  ctx.fillRect(x+5, y+5, CELL-10, 4);
  ctx.fillRect(x+5, y+5, 4, CELL-10);
}

function drawGhost(ctx, c, r, colorKey) {
  const x = c * CELL, y = r * CELL;
  const col = COLORS[colorKey] || '#888888';
  ctx.strokeStyle = col + '44';
  ctx.lineWidth = 1.5;
  ctx.setLineDash([4,4]);
  ctx.strokeRect(x+2, y+2, CELL-4, CELL-4);
  ctx.setLineDash([]);
}

function drawNext() {
  nCtx.fillStyle = '#ffffff';
  nCtx.fillRect(0, 0, nCanvas.width, nCanvas.height);
  if (!next) return;
  const s = 22;
  const rows = next.shape.length, cols = next.shape[0].length;
  const ox = Math.floor((nCanvas.width  - cols*s) / 2);
  const oy = Math.floor((nCanvas.height - rows*s) / 2);
  const col = COLORS[next.color];
  next.shape.forEach((row, r) =>
    row.forEach((val, c) => {
      if (!val) return;
      const x = ox+c*s, y = oy+r*s;
      nCtx.fillStyle = col;
      nCtx.fillRect(x+3, y+3, s-6, s-6);
      nCtx.strokeStyle = col;
      nCtx.lineWidth = 1.5;
      nCtx.strokeRect(x+1, y+1, s-2, s-2);
      nCtx.fillStyle = 'rgba(255,255,255,0.45)';
      nCtx.fillRect(x+3, y+3, s-6, 4);
    })
  );
}

// ── HUD ──
function updateHUD() {
  document.getElementById('scoreVal').textContent = score.toLocaleString();
  document.getElementById('highVal').textContent  = highScore.toLocaleString();
  document.getElementById('linesVal').textContent = lines;
  document.getElementById('levelVal').textContent = level;
  const pips = document.getElementById('levelPips');
  pips.innerHTML = '';
  for (let i = 1; i <= 10; i++) {
    const d = document.createElement('div');
    d.className = 'level-pip' + (i <= level ? ' on' : '');
    pips.appendChild(d);
  }
  document.getElementById('pieceStats').innerHTML =
    PIECE_KEYS.map(k =>
      `<div style="color:${COLORS[k]}">${k}: ${pieceCounts[k]||0}</div>`
    ).join('');
}

// ── Keyboard ──
document.addEventListener('keydown', e => {
  const overlayVisible = !document.getElementById('overlay').classList.contains('hidden');
  if (overlayVisible && !userPaused) return; // block if start screen shown
  if (gameOver) return;
  switch (e.code) {
    case 'ArrowLeft':  moveLeft();    break;
    case 'ArrowRight': moveRight();   break;
    case 'ArrowDown':  softDrop();    break;
    case 'ArrowUp':    rotate();      break;
    case 'Space':      hardDrop();    break;
    case 'KeyP':       togglePause(); break;
  }
  e.preventDefault();
});

// ── Touch ──
function touchAction(action) {
  if (gameOver || userPaused || clearing) return;
  ({ left:moveLeft, right:moveRight, rotate, down:softDrop, drop:hardDrop }[action] || (()=>{}))();
}
let sx=0, sy=0;
canvas.addEventListener('touchstart', e=>{ sx=e.touches[0].clientX; sy=e.touches[0].clientY; e.preventDefault(); },{passive:false});
canvas.addEventListener('touchend',   e=>{
  const dx=e.changedTouches[0].clientX-sx, dy=e.changedTouches[0].clientY-sy;
  if (Math.abs(dx)>Math.abs(dy)) { dx>20?moveRight():moveLeft(); }
  else { dy>20?hardDrop():rotate(); }
  e.preventDefault();
},{passive:false});

// ── Boot ──
updateHUD();
draw();