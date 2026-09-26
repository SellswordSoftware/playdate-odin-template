package cellular_liquid

// =================================================================
// Screen model (Playdate LCD: 400 x 240, 1 bit per pixel)
// =================================================================

SCREEN_W :: i32(400)
SCREEN_H :: i32(240)

// =================================================================
// Simulation grid: one cell maps to a 5 x 5 display pixel block.
// =================================================================

GRID_W :: i32(80)
GRID_H :: i32(48)
CELL_PX :: i32(5)

CELL_COUNT :: GRID_W * GRID_H

// Compile-time checks (negative array count fails the build).
// The grid must tile the screen exactly.
GRID_TILES_SCREEN_W :: [GRID_W * CELL_PX - SCREEN_W]byte
GRID_TILES_SCREEN_H :: [GRID_H * CELL_PX - SCREEN_H]byte
GRID_CELL_COUNT :: [CELL_COUNT - 3840]byte

// =================================================================
// Mass model (Q16: CAP = 1.0)
//
// Mass is stored in i32 so the transient compression range up to
// CAP_CEILING (1.10 x CAP = 72088) fits; i16 cannot hold it.
// =================================================================

CAP :: i32(65535)
// 8.0 x CAP. The ceiling must carry the hydrostatic head of the
// deepest pool (46 rows): head = rows * G_Q15 * K_PRESSURE_DEN /
// K_GRAVITY_DEN = 46 * 65534 = 3.01M, and the max pressure span is
// CAP + K_STIFF * (CAP_CEILING - CAP) = 3.74M. A high ceiling makes
// the liquid effectively incompressible (columns settle at their
// natural height instead of riding a stiff spring); rendering clamps
// coverage at CAP, so the extra compression range is invisible.
CAP_CEILING :: i32(524280)

// =================================================================
// Edges: interior only; the border ring is solid, so every edge
// touching it is dead and never stored.
// =================================================================

H_EDGES :: (GRID_W - 1) * GRID_H // 79 x 48 = 3792, edge (x,y) -> (x+1,y)
V_EDGES :: GRID_W * (GRID_H - 1) // 80 x 47 = 3760, edge (x,y) -> (x,y+1)

// Compile-time checks.
H_EDGES_CHECK :: [H_EDGES - 3792]byte
V_EDGES_CHECK :: [V_EDGES - 3760]byte

// =================================================================
// Simulation timing
// =================================================================

TICK_HZ :: 30
TICK_S :: 1.0 / 30.0

// =================================================================
// Flux tuning (step 6 consolidates these into one configuration
// block with presets; they are tuning defaults, not physical
// constants).
// =================================================================

// Compression pressure per unit of excess mass above CAP.
K_STIFF :: i32(8)

// Drive per unit pressure difference: (pA - pB) / K_PRESSURE_DEN.
// K_PRESSURE_DEN / K_GRAVITY_DEN must be >= 2 so gravity dominates
// the free-surface pressure drive (CAP / K_PRESSURE_DEN) and blobs
// fall as coherent bodies instead of spraying outward.
K_PRESSURE_DEN :: i32(32)

// Drive per unit Q15 gravity projection along the edge:
// gproj / K_GRAVITY_DEN. Must satisfy
// rows_max * G_Q15 * K_PRESSURE_DEN / K_GRAVITY_DEN <=
// CAP + K_STIFF * (CAP_CEILING - CAP) so the deepest pool can
// balance gravity.
K_GRAVITY_DEN :: i32(16)

// Flow retention per tick: flow = (flow + drive) * DRAG_NUM / DRAG_DEN.
DRAG_NUM :: i32(250)
DRAG_DEN :: i32(256)

// Cohesion threshold: a cell only exerts pressure above this fill
// level. Cells below it are "surface" cells that do not push their
// neighbors, which is what keeps blobs coherent instead of spraying
// apart at the free surface (the model's stand-in for surface
// tension). COHESION must keep the surface pressure drive
// (CAP - COHESION) / K_PRESSURE_DEN below the gravity drive
// G_Q15 / K_GRAVITY_DEN so gravity dominates free-surface motion.
COHESION :: i32(32767)

// Maximum |flow| per edge per tick (~0.37 cells of mass per tick).
// The clamp is part of the model: it bounds fall speed and keeps
// the i16 flow storage in range.
FLOW_CAP :: i16(24000)

// Flows with |flow| below this magnitude are zeroed, so a settled
// state reaches exactly zero flow (cohesion).
FLOW_DEADBAND :: i16(4)

// Q15 full scale: 32767 = 1 g.
G_Q15 :: i16(32767)
