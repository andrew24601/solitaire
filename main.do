import { createApp, appNewGame, appClick, appDragStart, appDragMove, appDragEnd, appCancelInteraction, appUpdate, appAutoComplete } from "./app-state"
import { Pile, SolitaireState } from "./game"
import { abs, cos, PI, sin, sqrt } from "std/math"
import {
  Blend,
  Camera,
  Clear,
  Color,
  CullMode,
  Depth,
  GameEventKind,
  GameRenderMode,
  Key,
  Mat4,
  Point,
  Point3,
  RenderPassDescriptor,
  Rotation,
  SimpleMesh,
  SimpleMeshBuilder,
  SimpleModelBatch,
  SimpleModelInstance,
  GameSurface,
  Texture,
  Transform,
  Vec2,
  drawSimpleModelBatch,
  drawSimpleMesh,
  initGameApp,
} from "std/game"

const CARD_COLUMNS: int = 14
const CARD_ROWS: int = 4
const CARD_WIDTH: double = 80.0
const CARD_HEIGHT: double = 120.0
const CLICK_THRESHOLD: double = 5.0
const FOV_Y: double = 65.0 * (PI / 180.0)
const CAMERA_DISTANCE: double = 700.0
const CAMERA_NEAR: double = 400.0
const CAMERA_FAR: double = 950.0
const AUTO_CAMERA_MIN_PITCH: double = 1.0471976
const AUTO_CAMERA_MAX_PITCH: double = 1.4765485
const AUTO_CAMERA_MIN_DEPTH: double = 400.0
const AUTO_CAMERA_MAX_DEPTH: double = 600.0
const AUTO_CAMERA_VIEWPORT_USAGE: double = 0.96
const AUTO_CAMERA_TOP_PADDING: double = 0.15
const AUTO_CAMERA_MIN_SCALE: double = 0.5
const AUTO_CAMERA_MAX_SCALE: double = 3.0
const AUTO_CAMERA_SMOOTH_TIME: double = 0.28
const DRAW_LAYER_STEP: double = 0.35
const FLIP_LAYER_BONUS: int = 4
const DRAG_LAYER_START: int = 32
const CARD_INSTANCE_COUNT: int = 52
const PLACEHOLDER_INSTANCE_COUNT: int = 12
const ATLAS_UV_SCALE_X: double = 1.0 / double(CARD_COLUMNS)
const ATLAS_UV_SCALE_Y: double = 1.0 / double(CARD_ROWS)
const RESTART_BUTTON_SIZE: double = 80.0
const RESTART_BUTTON_MARGIN: double = 18.0
const RESTART_SPIN_DURATION: float = 0.28f

class PointerState {
  down: bool = false
  dragging: bool = false
  uiPress: bool = false
  startX: double = 0.0
  startY: double = 0.0
}

class RestartButton {
  x: double = 0.0
  y: double = 0.0
  size: double = 80.0
  hovered: bool = false
  pressed: bool = false
  spinTimeRemaining: float = 0.0f
}

class BoardBounds {
  minX: double = 0.0
  maxX: double = 0.0
  minZ: double = 0.0
  maxZ: double = 0.0
}

class AutoCameraFrame {
  targetX: double = 0.0
  targetY: double = 0.0
  targetZ: double = 0.0
  distance: double = 700.0
  pitch: double = 1.28
  scale: double = 1.45
  panX: double = 0.0
  panY: double = -0.08
}

class AutoCamera {
  targetX: double = 0.0
  targetY: double = 0.0
  targetZ: double = 0.0
  distance: double = 700.0
  pitch: double = 1.28
  frameScale: double = 1.45
  framePanX: double = 0.0
  framePanY: double = -0.08
  initialized: bool = false

  targetVelocityX: double = 0.0
  targetVelocityZ: double = 0.0
  pitchVelocity: double = 0.0
  scaleVelocity: double = 0.0
  panXVelocity: double = 0.0
  panYVelocity: double = 0.0
}

class SmoothResult {
  value: double = 0.0
  velocity: double = 0.0
}

class RenderItem {
  cardIndex: int = -1
  placeholder: bool = false
  column: int = 0
  row: int = 0
  x: float = 0.0f
  z: float = 0.0f
  layer: int = 0
  alpha: double = 1.0
  animating: bool = false
}

class CardRenderScene {
  fronts: SimpleModelBatch
  backs: SimpleModelBatch
  placeholders: SimpleModelBatch
  frontInstances: SimpleModelInstance[] = []
  backInstances: SimpleModelInstance[] = []
  placeholderInstances: SimpleModelInstance[] = []
}

function atlasCell(column: int, row: int): Vec2 {
  return Vec2.xy(double(column) / double(CARD_COLUMNS), double(row) / double(CARD_ROWS))
}

function atlasScale(): Vec2 {
  return Vec2.xy(ATLAS_UV_SCALE_X, ATLAS_UV_SCALE_Y)
}

function includePoint(bounds: BoardBounds, x: double, z: double): void {
  if x < bounds.minX { bounds.minX = x }
  if x > bounds.maxX { bounds.maxX = x }
  if z < bounds.minZ { bounds.minZ = z }
  if z > bounds.maxZ { bounds.maxZ = z }
}

function includeCard(bounds: BoardBounds, x: float, z: float): void {
  includePoint(bounds, double(x) - CARD_WIDTH * 0.5, double(z) - CARD_HEIGHT * 0.5)
  includePoint(bounds, double(x) + CARD_WIDTH * 0.5, double(z) + CARD_HEIGHT * 0.5)
}

function computeBounds(state: SolitaireState): BoardBounds {
  bounds := BoardBounds {
    minX: -470.0,
    maxX: 260.0,
    minZ: -130.0,
    maxZ: 300.0,
  }
  includeCard(bounds, state.stock.x, state.stock.z)
  includeCard(bounds, state.waste.x, state.waste.z)
  for i of 0..3 {
    pile := state.foundation(i)
    includeCard(bounds, pile.x, pile.z)
  }
  for i of 0..6 {
    pile := state.tableau(i)
    includeCard(bounds, pile.x, pile.z)
  }
  for card of state.cards {
    includeCard(bounds, card.x, card.z)
  }
  return bounds
}

function minDouble(a: double, b: double): double {
  return if a < b then a else b
}

function clampDouble(value: double, minValue: double, maxValue: double): double {
  if value < minValue { return minValue }
  if value > maxValue { return maxValue }
  return value
}

function maxDouble(a: double, b: double): double {
  return if a > b then a else b
}

function clampToSurface(point: Point, width: double, height: double): Point {
  return Point(
    clampDouble(point.x, 0.0, width),
    clampDouble(point.y, 0.0, height),
  )
}

function layoutRestartButton(surface: GameSurface, button: RestartButton): void {
  button.x = double(surface.width()) - button.size - RESTART_BUTTON_MARGIN
  button.y = RESTART_BUTTON_MARGIN
}

function restartHitTest(button: RestartButton, point: Point): bool {
  return point.x >= button.x && point.x <= button.x + button.size &&
    point.y >= button.y && point.y <= button.y + button.size
}

function updateRestartHover(button: RestartButton, point: Point): void {
  button.hovered = restartHitTest(button, point)
  if button.pressed && !button.hovered {
    button.pressed = false
  }
}

function pressRestartButton(button: RestartButton, point: Point): bool {
  updateRestartHover(button, point)
  if button.hovered {
    button.pressed = true
    return true
  }
  return false
}

function releaseRestartButton(button: RestartButton, point: Point): bool {
  wasPressed := button.pressed
  updateRestartHover(button, point)
  button.pressed = false
  if wasPressed && button.hovered {
    button.spinTimeRemaining = RESTART_SPIN_DURATION
    return true
  }
  return false
}

function updateRestartButton(button: RestartButton, deltaTime: float): bool {
  if button.spinTimeRemaining <= 0.0f {
    return false
  }
  button.spinTimeRemaining = button.spinTimeRemaining - deltaTime
  if button.spinTimeRemaining < 0.0f {
    button.spinTimeRemaining = 0.0f
  }
  return button.spinTimeRemaining > 0.0f
}

function restartRotation(button: RestartButton): double {
  if button.spinTimeRemaining <= 0.0f {
    return 0.0
  }
  progress := 1.0 - double(button.spinTimeRemaining) / double(RESTART_SPIN_DURATION)
  eased := 1.0 - (1.0 - progress) * (1.0 - progress)
  return PI * 2.0 * eased
}

function rotatedPoint(cx: double, cy: double, x: double, y: double, rotationCos: double, rotationSin: double): Point {
  dx := x - cx
  dy := y - cy
  return Point(cx + dx * rotationCos - dy * rotationSin, cy + dx * rotationSin + dy * rotationCos)
}

function addRestartVertex(builder: SimpleMeshBuilder, point: Point, color: Color, z: double): int {
  return builder.vertex{ position: Point3(point.x, point.y, z), color }
}

function addRestartTriangle(builder: SimpleMeshBuilder, a: Point, b: Point, c: Point, color: Color, z: double): void {
  ai := addRestartVertex(builder, a, color, z)
  bi := addRestartVertex(builder, b, color, z)
  ci := addRestartVertex(builder, c, color, z)
  builder.triangle(ai, bi, ci)
}

function addRestartQuad(builder: SimpleMeshBuilder, a: Point, b: Point, c: Point, d: Point, color: Color, z: double): void {
  ai := addRestartVertex(builder, a, color, z)
  bi := addRestartVertex(builder, b, color, z)
  ci := addRestartVertex(builder, c, color, z)
  di := addRestartVertex(builder, d, color, z)
  builder.triangle(ai, bi, ci)
  builder.triangle(ai, ci, di)
}

function restartButtonColor(button: RestartButton): Color {
  if button.pressed {
    return Color(0.04, 0.13, 0.09, 0.95)
  }
  if button.hovered {
    return Color(0.08, 0.26, 0.16, 0.90)
  }
  return Color(0.045, 0.17, 0.11, 0.82)
}

function restartIconColor(button: RestartButton): Color {
  alpha := if button.pressed then 0.82 else 1.0
  return Color(0.94, 1.0, 0.90, alpha)
}

function createRestartButtonMesh(surface: GameSurface, button: RestartButton): SimpleMesh {
  builder := SimpleMeshBuilder.create()
  cx := button.x + button.size * 0.5
  cy := button.y + button.size * 0.5
  bgColor := restartButtonColor(button)
  iconColor := restartIconColor(button)
  bgRadius := button.size * 0.5
  bgSegments := 36
  z := 0.0

  center := Point(cx, cy)
  for let i = 0; i < bgSegments; i += 1 {
    a0 := PI * 2.0 * double(i) / double(bgSegments)
    a1 := PI * 2.0 * double(i + 1) / double(bgSegments)
    addRestartTriangle(
      builder,
      center,
      Point(cx + cos(a0) * bgRadius, cy + sin(a0) * bgRadius),
      Point(cx + cos(a1) * bgRadius, cy + sin(a1) * bgRadius),
      bgColor,
      z,
    )
  }

  r := button.size * 0.30
  thickness := button.size * 0.075
  rotation := restartRotation(button)
  rotationCos := cos(rotation)
  rotationSin := sin(rotation)
  segments := 24
  startAngle := -PI * 0.2
  endAngle := PI * 1.4

  for let i = 0; i < segments; i += 1 {
    t0 := double(i) / double(segments)
    t1 := double(i + 1) / double(segments)
    a0 := startAngle + (endAngle - startAngle) * t0
    a1 := startAngle + (endAngle - startAngle) * t1
    rInner := r - thickness * 0.5
    rOuter := r + thickness * 0.5

    p0In := rotatedPoint(cx, cy, cx + cos(a0) * rInner, cy + sin(a0) * rInner, rotationCos, rotationSin)
    p0Out := rotatedPoint(cx, cy, cx + cos(a0) * rOuter, cy + sin(a0) * rOuter, rotationCos, rotationSin)
    p1In := rotatedPoint(cx, cy, cx + cos(a1) * rInner, cy + sin(a1) * rInner, rotationCos, rotationSin)
    p1Out := rotatedPoint(cx, cy, cx + cos(a1) * rOuter, cy + sin(a1) * rOuter, rotationCos, rotationSin)
    addRestartQuad(builder, p0In, p0Out, p1Out, p1In, iconColor, z + 0.01)
  }

  arrowSize := thickness * 3.5
  angle := endAngle
  c := cos(angle)
  s := sin(angle)
  tx := -s
  ty := c
  nx := c
  ny := s
  p0 := rotatedPoint(cx, cy, cx + c * r + tx * arrowSize * 0.5, cy + s * r + ty * arrowSize * 0.5, rotationCos, rotationSin)
  p1 := rotatedPoint(cx, cy, cx + c * r - tx * arrowSize * 0.5 + nx * arrowSize * 0.6, cy + s * r - ty * arrowSize * 0.5 + ny * arrowSize * 0.6, rotationCos, rotationSin)
  p2 := rotatedPoint(cx, cy, cx + c * r - tx * arrowSize * 0.5 - nx * arrowSize * 0.6, cy + s * r - ty * arrowSize * 0.5 - ny * arrowSize * 0.6, rotationCos, rotationSin)
  addRestartTriangle(builder, p0, p1, p2, iconColor, z + 0.01)

  return builder.build(surface)
}

function frameTransform(scale: double, panX: double, panY: double): Mat4 {
  return Mat4 {
    m00: scale, m01: 0.0, m02: 0.0, m03: panX,
    m10: 0.0, m11: scale, m12: 0.0, m13: panY,
    m20: 0.0, m21: 0.0, m22: 1.0, m23: 0.0,
    m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
  }
}

function normalizeLength(x: double, y: double, z: double): double {
  len := sqrt(x * x + y * y + z * z)
  return if len > 0.000001 then len else 1.0
}

function lookAtMatrix(eyeX: double, eyeY: double, eyeZ: double, targetX: double, targetY: double, targetZ: double): Mat4 {
  let fx = targetX - eyeX
  let fy = targetY - eyeY
  let fz = targetZ - eyeZ
  fl := sqrt(fx * fx + fy * fy + fz * fz)
  fx = fx / fl
  fy = fy / fl
  fz = fz / fl

  let sx = fy * 0.0 - fz * 1.0
  let sy = fz * 0.0 - fx * 0.0
  let sz = fx * 1.0 - fy * 0.0
  sl := sqrt(sx * sx + sy * sy + sz * sz)
  sx = sx / sl
  sy = sy / sl
  sz = sz / sl

  ux := sy * fz - sz * fy
  uy := sz * fx - sx * fz
  uz := sx * fy - sy * fx

  return Mat4 {
    m00: sx, m01: sy, m02: sz, m03: -(sx * eyeX + sy * eyeY + sz * eyeZ),
    m10: ux, m11: uy, m12: uz, m13: -(ux * eyeX + uy * eyeY + uz * eyeZ),
    m20: -fx, m21: -fy, m22: -fz, m23: fx * eyeX + fy * eyeY + fz * eyeZ,
    m30: 0.0, m31: 0.0, m32: 0.0, m33: 1.0,
  }
}

function cameraViewMatrix(camera: AutoCamera): Mat4 {
  eyeX := camera.targetX
  eyeY := camera.targetY + camera.distance * sin(camera.pitch)
  eyeZ := camera.targetZ + camera.distance * cos(camera.pitch)
  return lookAtMatrix(eyeX, eyeY, eyeZ, camera.targetX, camera.targetY, camera.targetZ)
}

function autoCameraMvp(camera: AutoCamera, width: double, height: double): Mat4 {
  aspect := width / height
  proj := Mat4.perspective(FOV_Y, aspect, CAMERA_NEAR, CAMERA_FAR)
  view := cameraViewMatrix(camera)
  return frameTransform(camera.frameScale, camera.framePanX, camera.framePanY).multiply(proj).multiply(view)
}

function autoCameraTargetMvp(frame: AutoCameraFrame, width: double, height: double): Mat4 {
  scratch := AutoCamera {
    targetX: frame.targetX,
    targetY: frame.targetY,
    targetZ: frame.targetZ,
    distance: frame.distance,
    pitch: frame.pitch,
    frameScale: 1.0,
    framePanX: 0.0,
    framePanY: 0.0,
    initialized: true,
  }
  return autoCameraMvp(scratch, width, height)
}

function smoothDamp(
  current: double,
  target: double,
  velocity: double,
  smoothTime: double,
  deltaTime: double
): SmoothResult {
  st := if smoothTime < 0.0001 then 0.0001 else smoothTime
  omega := 2.0 / st
  x := omega * deltaTime
  expFactor := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

  let change = current - target
  originalTo := target
  maxChange := 1000.0 * st
  if change > maxChange { change = maxChange }
  if change < -maxChange { change = -maxChange }

  adjustedTarget := current - change
  temp := (velocity + omega * change) * deltaTime
  newVelocity := (velocity - omega * temp) * expFactor
  let result = adjustedTarget + (change + temp) * expFactor

  overshoot := (originalTo - current > 0.0) == (result > originalTo)
  if overshoot {
    result = originalTo
    return SmoothResult { value: result, velocity: 0.0 }
  }

  return SmoothResult { value: result, velocity: newVelocity }
}

function applyAutoCameraFrame(camera: AutoCamera, frame: AutoCameraFrame): void {
  camera.targetX = frame.targetX
  camera.targetY = frame.targetY
  camera.targetZ = frame.targetZ
  camera.distance = frame.distance
  camera.pitch = frame.pitch
  camera.frameScale = frame.scale
  camera.framePanX = frame.panX
  camera.framePanY = frame.panY
  camera.targetVelocityX = 0.0
  camera.targetVelocityZ = 0.0
  camera.pitchVelocity = 0.0
  camera.scaleVelocity = 0.0
  camera.panXVelocity = 0.0
  camera.panYVelocity = 0.0
  camera.initialized = true
}

function updateAutoCamera(camera: AutoCamera, target: AutoCameraFrame, deltaTime: double): bool {
  if !camera.initialized {
    applyAutoCameraFrame(camera, target)
    return false
  }

  rTargetX := smoothDamp(camera.targetX, target.targetX, camera.targetVelocityX, AUTO_CAMERA_SMOOTH_TIME, deltaTime)
  camera.targetX = rTargetX.value
  camera.targetVelocityX = rTargetX.velocity

  rTargetZ := smoothDamp(camera.targetZ, target.targetZ, camera.targetVelocityZ, AUTO_CAMERA_SMOOTH_TIME, deltaTime)
  camera.targetZ = rTargetZ.value
  camera.targetVelocityZ = rTargetZ.velocity

  rPitch := smoothDamp(camera.pitch, target.pitch, camera.pitchVelocity, AUTO_CAMERA_SMOOTH_TIME, deltaTime)
  camera.pitch = rPitch.value
  camera.pitchVelocity = rPitch.velocity

  rScale := smoothDamp(camera.frameScale, target.scale, camera.scaleVelocity, AUTO_CAMERA_SMOOTH_TIME, deltaTime)
  camera.frameScale = rScale.value
  camera.scaleVelocity = rScale.velocity

  rPanX := smoothDamp(camera.framePanX, target.panX, camera.panXVelocity, AUTO_CAMERA_SMOOTH_TIME, deltaTime)
  camera.framePanX = rPanX.value
  camera.panXVelocity = rPanX.velocity

  rPanY := smoothDamp(camera.framePanY, target.panY, camera.panYVelocity, AUTO_CAMERA_SMOOTH_TIME, deltaTime)
  camera.framePanY = rPanY.value
  camera.panYVelocity = rPanY.velocity
  camera.distance = target.distance

  dTargetX := camera.targetX - target.targetX
  dTargetZ := camera.targetZ - target.targetZ
  dPitch := camera.pitch - target.pitch
  dScale := camera.frameScale - target.scale
  dPanX := camera.framePanX - target.panX
  dPanY := camera.framePanY - target.panY
  distSq := dTargetX * dTargetX +
    dTargetZ * dTargetZ +
    dPitch * dPitch * 100.0 +
    dScale * dScale +
    dPanX * dPanX +
    dPanY * dPanY

  return distSq > 0.0001
}

function computeIdealAutoFrame(state: SolitaireState, width: double, height: double): AutoCameraFrame {
  bounds := computeBounds(state)
  frame := AutoCameraFrame {}

  boundsDepth := bounds.maxZ - bounds.minZ
  let t = (boundsDepth - AUTO_CAMERA_MIN_DEPTH) / (AUTO_CAMERA_MAX_DEPTH - AUTO_CAMERA_MIN_DEPTH)
  t = clampDouble(t, 0.0, 1.0)
  t = t * t * (3.0 - 2.0 * t)

  frame.pitch = AUTO_CAMERA_MIN_PITCH + t * (AUTO_CAMERA_MAX_PITCH - AUTO_CAMERA_MIN_PITCH)
  frame.targetX = (bounds.minX + bounds.maxX) * 0.5
  frame.targetY = 0.0
  frame.targetZ = (bounds.minZ + bounds.maxZ) * 0.5
  frame.distance = CAMERA_DISTANCE

  mvp := autoCameraTargetMvp(frame, width, height)
  c0 := mvp.projectPoint(Point3(bounds.minX, 0.0, bounds.minZ))
  c1 := mvp.projectPoint(Point3(bounds.maxX, 0.0, bounds.minZ))
  c2 := mvp.projectPoint(Point3(bounds.minX, 0.0, bounds.maxZ))
  c3 := mvp.projectPoint(Point3(bounds.maxX, 0.0, bounds.maxZ))

  ndcMinX := minDouble(minDouble(c0.x, c1.x), minDouble(c2.x, c3.x))
  ndcMaxX := maxDouble(maxDouble(c0.x, c1.x), maxDouble(c2.x, c3.x))
  ndcMinY := minDouble(minDouble(c0.y, c1.y), minDouble(c2.y, c3.y))
  ndcMaxY := maxDouble(maxDouble(c0.y, c1.y), maxDouble(c2.y, c3.y))

  ndcWidth := maxDouble(ndcMaxX - ndcMinX, 0.0001)
  ndcHeight := maxDouble(ndcMaxY - ndcMinY, 0.0001)
  viewportSize := 2.0 * AUTO_CAMERA_VIEWPORT_USAGE
  scaleX := viewportSize / ndcWidth
  scaleY := (viewportSize - AUTO_CAMERA_TOP_PADDING) / ndcHeight
  frame.scale = clampDouble(minDouble(scaleX, scaleY), AUTO_CAMERA_MIN_SCALE, AUTO_CAMERA_MAX_SCALE)

  ndcCenterX := (ndcMinX + ndcMaxX) * 0.5
  ndcCenterY := (ndcMinY + ndcMaxY) * 0.5
  frame.panX = -ndcCenterX * frame.scale
  frame.panY = -ndcCenterY * frame.scale - AUTO_CAMERA_TOP_PADDING * 0.5

  return frame
}

function solitaireCamera(autoCamera: AutoCamera, width: double, height: double): Camera {
  return Camera.identity().withView(autoCameraMvp(autoCamera, width, height))
}

function perspectiveScreenToWorld(camera: AutoCamera, x: double, y: double, width: double, height: double): Point {
  ndcX := (x / width) * 2.0 - 1.0
  ndcY := 1.0 - (y / height) * 2.0
  inverseMvp := autoCameraMvp(camera, width, height).inverse()
  near := inverseMvp.projectPoint(Point3(ndcX, ndcY, 0.0))
  far := inverseMvp.projectPoint(Point3(ndcX, ndcY, 1.0))

  let dirX = far.x - near.x
  let dirY = far.y - near.y
  let dirZ = far.z - near.z
  len := normalizeLength(dirX, dirY, dirZ)
  dirX = dirX / len
  dirY = dirY / len
  dirZ = dirZ / len

  if abs(dirY) > 0.000001 {
    t := -near.y / dirY
    if t >= 0.0 {
      return Point(near.x + dirX * t, near.z + dirZ * t)
    }
  }
  return Point(camera.targetX, camera.targetZ)
}

function addDraggedCards(state: SolitaireState): Set<int> {
  let dragged: Set<int> = []
  if !state.isDragging || state.selectedPileType < 0 {
    return dragged
  }

  if state.selectedPileType == 0 {
    pile := state.tableau(state.selectedPileIndex)
    for i of state.selectedCardIndex..<pile.cardIndices.length {
      idx := pile.cardIndices[i]
      dragged.add(idx)
    }
  } else if state.selectedPileType == 1 {
    idx := state.waste.topCardIndex()
    dragged.add(idx)
  } else if state.selectedPileType == 2 {
    pile := state.foundation(state.selectedPileIndex)
    idx := pile.topCardIndex()
    dragged.add(idx)
  }
  return dragged
}

function orderedDraggedCards(state: SolitaireState): int[] {
  dragged: int[] := []
  if !state.isDragging || state.selectedPileType < 0 {
    return dragged
  }

  if state.selectedPileType == 0 {
    pile := state.tableau(state.selectedPileIndex)
    for i of state.selectedCardIndex..<pile.cardIndices.length {
      dragged.push(pile.cardIndices[i])
    }
  } else if state.selectedPileType == 1 {
    dragged.push(state.waste.topCardIndex())
  } else if state.selectedPileType == 2 {
    dragged.push(state.foundation(state.selectedPileIndex).topCardIndex())
  }
  return dragged
}

function appendRenderItem(target: RenderItem[], item: RenderItem): void {
  target.push(item)
}

function appendCardItem(target: RenderItem[], state: SolitaireState, cardIndex: int, layer: int): void {
  if cardIndex < 0 || cardIndex >= state.cards.length { return }
  card := state.cards[cardIndex]
  appendRenderItem(target, RenderItem {
    cardIndex,
    layer,
    animating: card.flipPhase != 0 || (state.moveAnimActive && cardIndex == state.moveCardIndex) || (state.dealAnimActive && cardIndex == state.dealCardIndex),
  })
}

function cardStackLayer(cardIndex: int, pile: Pile): int {
  for i of 0..<pile.cardIndices.length {
    if pile.cardIndices[i] == cardIndex {
      return i + 1
    }
  }
  return 1
}

function cardRenderLayer(state: SolitaireState, cardIndex: int): int {
  for i of 0..3 {
    pile := state.foundation(i)
    for idx of pile.cardIndices {
      if idx == cardIndex { return cardStackLayer(cardIndex, pile) }
    }
  }
  for idx of state.stock.cardIndices {
    if idx == cardIndex { return cardStackLayer(cardIndex, state.stock) }
  }
  for idx of state.waste.cardIndices {
    if idx == cardIndex { return cardStackLayer(cardIndex, state.waste) }
  }
  for i of 0..6 {
    pile := state.tableau(i)
    for idx of pile.cardIndices {
      if idx == cardIndex { return cardStackLayer(cardIndex, pile) }
    }
  }
  return 1
}

function buildRenderItems(state: SolitaireState): RenderItem[] {
  items: RenderItem[] := []
  staticItems: RenderItem[] := []
  animatingItems: RenderItem[] := []
  ordered: int[] := []

  for i of 0..3 {
    pile := state.foundation(i)
    appendRenderItem(items, RenderItem { placeholder: true, column: 0, row: i, x: pile.x, z: pile.z, layer: 0, alpha: 0.3 })
  }
  appendRenderItem(items, RenderItem { placeholder: true, column: 13, row: 0, x: state.stock.x, z: state.stock.z, layer: 0, alpha: 0.3 })
  for i of 0..6 {
    pile := state.tableau(i)
    appendRenderItem(items, RenderItem { placeholder: true, column: 13, row: 0, x: pile.x, z: pile.z, layer: 0, alpha: 0.3 })
  }

  draggedCards := orderedDraggedCards(state)
  dragged := addDraggedCards(state)
  for i of 0..3 {
    pile := state.foundation(i)
    for idx of pile.cardIndices {
      ordered.push(idx)
    }
  }
  for idx of state.stock.cardIndices {
    ordered.push(idx)
  }
  for idx of state.waste.cardIndices {
    ordered.push(idx)
  }

  let maxDepth = 0
  for i of 0..6 {
    pile := state.tableau(i)
    if pile.cardIndices.length > maxDepth { maxDepth = pile.cardIndices.length }
  }
  for let depth = 0; depth < maxDepth; depth += 1 {
    for pile of 0..6 {
      tab := state.tableau(pile)
      if depth < tab.cardIndices.length {
        ordered.push(tab.cardIndices[depth])
      }
    }
  }

  for idx of ordered {
    if !dragged.has(idx) {
      appendCardItem(staticItems, state, idx, cardRenderLayer(state, idx))
    }
  }
  let draggedLayer = DRAG_LAYER_START
  for idx of draggedCards {
    appendCardItem(staticItems, state, idx, draggedLayer)
    draggedLayer += 1
  }

  for item of staticItems {
    if item.animating {
      animatingItems.push(item)
    } else {
      items.push(item)
    }
  }
  for item of animatingItems {
    items.push(item)
  }
  return items
}

function cardTransform(x: double, y: double, z: double, rotationRadians: double): Transform {
  return Transform.identity()
    .withPosition(Point3(x, y, z))
    .withRotation(Rotation.z(rotationRadians * 180.0 / PI))
}

function createCardFrontMesh(surface: GameSurface): SimpleMesh {
  halfW := CARD_WIDTH * 0.5
  halfH := CARD_HEIGHT * 0.5
  return SimpleMeshBuilder
    .create()
    .quad{
      a: Point3(-halfW, 0.0, halfH),
      b: Point3(halfW, 0.0, halfH),
      c: Point3(halfW, 0.0, -halfH),
      d: Point3(-halfW, 0.0, -halfH),
      color: Color.white,
      uvA: Point(0.0, 1.0),
      uvB: Point(1.0, 1.0),
      uvC: Point(1.0, 0.0),
      uvD: Point(0.0, 0.0),
    }
    .build(surface)
}

function createCardBackMesh(surface: GameSurface): SimpleMesh {
  halfW := CARD_WIDTH * 0.5
  halfH := CARD_HEIGHT * 0.5
  return SimpleMeshBuilder
    .create()
    .quad{
      a: Point3(-halfW, 0.0, halfH),
      b: Point3(-halfW, 0.0, -halfH),
      c: Point3(halfW, 0.0, -halfH),
      d: Point3(halfW, 0.0, halfH),
      color: Color.white,
      uvA: Point(1.0, 1.0),
      uvB: Point(1.0, 0.0),
      uvC: Point(0.0, 0.0),
      uvD: Point(0.0, 1.0),
    }
    .build(surface)
}

function createCardRenderScene(surface: GameSurface, atlas: Texture): CardRenderScene {
  frontMesh := createCardFrontMesh(surface)
  backMesh := createCardBackMesh(surface)
  fronts := SimpleModelBatch { surface: surface, mesh: frontMesh, texture: atlas, capacity: CARD_INSTANCE_COUNT }
  backs := SimpleModelBatch { surface: surface, mesh: backMesh, texture: atlas, capacity: CARD_INSTANCE_COUNT }
  placeholders := SimpleModelBatch { surface: surface, mesh: frontMesh, texture: atlas, capacity: PLACEHOLDER_INSTANCE_COUNT }
  scene := CardRenderScene { fronts: fronts, backs: backs, placeholders: placeholders }

  uvScale := atlasScale()
  for index of 0..<CARD_INSTANCE_COUNT {
    suit := index \ 13
    rank := index % 13
    scene.frontInstances.push(fronts.add{
      transform: cardTransform(0.0, 0.0, 0.0, 0.0),
      uvOffset: atlasCell(rank, suit),
      uvScale,
    })
    scene.backInstances.push(backs.add{
      transform: cardTransform(0.0, 0.0, 0.0, PI),
      uvOffset: atlasCell(13, 0),
      uvScale,
    })
  }

  for index of 0..<PLACEHOLDER_INSTANCE_COUNT {
    scene.placeholderInstances.push(placeholders.add{
      transform: cardTransform(0.0, 0.0, 0.0, 0.0),
      uvOffset: atlasCell(13, 0),
      uvScale,
    })
  }

  return scene
}

function updateCardInstance(scene: CardRenderScene, state: SolitaireState, cardIndex: int, layer: int): void {
  if cardIndex < 0 || cardIndex >= CARD_INSTANCE_COUNT || cardIndex >= state.cards.length { return }
  card := state.cards[cardIndex]
  renderLayer := if card.flipPhase != 0 then layer + FLIP_LAYER_BONUS else layer
  layerLift := double(renderLayer) * DRAW_LAYER_STEP
  let rot = double(card.currentRotation)
  if card.flipPhase == 0 {
    rot = if card.faceUp then 0.0 else PI
  }

  transform := cardTransform(
    double(card.x),
    double(card.y + card.currentLift) + layerLift,
    double(card.z),
    rot,
  )

  scene.frontInstances[cardIndex].setTransform(transform)
  scene.frontInstances[cardIndex].setTint(Color.white)
  scene.backInstances[cardIndex].setTransform(transform)
  scene.backInstances[cardIndex].setTint(Color.white)
}

function updatePlaceholderInstance(scene: CardRenderScene, item: RenderItem, layer: int, placeholderIndex: int): void {
  if placeholderIndex < 0 || placeholderIndex >= PLACEHOLDER_INSTANCE_COUNT { return }
  instance := scene.placeholderInstances[placeholderIndex]
  layerLift := double(layer) * DRAW_LAYER_STEP
  instance.setTransform(cardTransform(double(item.x), layerLift, double(item.z), 0.0))
  instance.setTint(Color(1.0, 1.0, 1.0, item.alpha))
  instance.setUvOffset(atlasCell(item.column, item.row))
}

function updateCardRenderScene(scene: CardRenderScene, state: SolitaireState): void {
  items := buildRenderItems(state)
  let placeholderIndex = 0
  for index of 0..<items.length {
    item := items[index]
    if item.placeholder {
      updatePlaceholderInstance(scene, item, item.layer, placeholderIndex)
      placeholderIndex += 1
    } else {
      updateCardInstance(scene, state, item.cardIndex, item.layer)
    }
  }
}

function runSolitaire(): Result<void, string> {
  app := initGameApp{ title: "Doof Solitaire", renderMode: GameRenderMode.Requested }
  try atlas := app.loadTextureResource("images/card_atlas.png")
  game := createApp()
  pointer := PointerState {}
  renderScene := createCardRenderScene(app.surface, atlas)
  restartButton := RestartButton {}
  autoCamera := AutoCamera {}
  applyAutoCameraFrame(
    autoCamera,
    computeIdealAutoFrame(game.state, double(app.surface.width()), double(app.surface.height())),
  )
  layoutRestartButton(app.surface, restartButton)

  app.key(Key.Escape).onPressed((): void => {
    if !appCancelInteraction(game) {
      app.stop()
    } else {
      app.requestRender()
    }
  })
  app.key(Key.N).onPressed((): void => {
    appNewGame(game)
    app.requestRender()
  })
  app.key(Key.A).onPressed((): void => {
    appAutoComplete(game)
    app.requestRender()
  })

  screenPointer := app.screenPointer()
  screenPointer.onPressed((point): void => {
    surfacePoint := clampToSurface(point, double(app.surface.width()), double(app.surface.height()))
    pointer.uiPress = pressRestartButton(restartButton, surfacePoint)
    if pointer.uiPress {
      pointer.down = false
      pointer.dragging = false
      app.requestRender()
      return
    }
    pointer.down = true
    pointer.dragging = false
    pointer.startX = surfacePoint.x
    pointer.startY = surfacePoint.y
  })
  screenPointer.onMoved((point): void => {
    surfacePoint := clampToSurface(point, double(app.surface.width()), double(app.surface.height()))
    updateRestartHover(restartButton, surfacePoint)
    app.requestRender()
    if !pointer.down || pointer.uiPress { return }
    width := double(app.surface.width())
    height := double(app.surface.height())
    world := perspectiveScreenToWorld(autoCamera, surfacePoint.x, surfacePoint.y, width, height)
    if !pointer.dragging {
      dx := surfacePoint.x - pointer.startX
      dy := surfacePoint.y - pointer.startY
      if dx * dx + dy * dy > CLICK_THRESHOLD * CLICK_THRESHOLD {
        start := perspectiveScreenToWorld(autoCamera, pointer.startX, pointer.startY, width, height)
        appDragStart(game, float(start.x), float(start.y))
        pointer.dragging = true
        app.requestRender()
      }
    }
    if pointer.dragging {
      appDragMove(game, float(world.x), float(world.y))
      app.requestRender()
    }
  })
  screenPointer.onReleased((point): void => {
    surfacePoint := clampToSurface(point, double(app.surface.width()), double(app.surface.height()))
    if pointer.uiPress {
      if releaseRestartButton(restartButton, surfacePoint) {
        appNewGame(game)
        app.requestRender()
      }
      pointer.down = false
      pointer.dragging = false
      pointer.uiPress = false
      return
    }
    width := double(app.surface.width())
    height := double(app.surface.height())
    world := perspectiveScreenToWorld(autoCamera, surfacePoint.x, surfacePoint.y, width, height)
    if pointer.dragging {
      appDragEnd(game, float(world.x), float(world.y))
      app.requestRender()
    } else {
      if appClick(game, float(world.x), float(world.y)) {
        app.requestRender()
      }
    }
    pointer.down = false
    pointer.dragging = false
    pointer.uiPress = false
  })

  app.onEvent((event): void => {
    if event.kind() == GameEventKind.CloseRequested {
      app.stop()
    } else if event.kind() == GameEventKind.Resized {
      layoutRestartButton(app.surface, restartButton)
      app.requestRender()
    }
  })

  app.onRender((renderer): void => {
    animating := appUpdate(game, 1.0f / 60.0f)
    buttonAnimating := updateRestartButton(restartButton, 1.0f / 60.0f)
    updateCardRenderScene(renderScene, game.state)
    width := double(app.surface.width())
    height := double(app.surface.height())
    targetFrame := computeIdealAutoFrame(game.state, width, height)
    cameraMoving := updateAutoCamera(autoCamera, targetFrame, 1.0 / 60.0)
    camera := solitaireCamera(autoCamera, width, height)
    renderer.pass(
      RenderPassDescriptor {
        camera,
        clear: Clear.colorDepth(Color(0.02, 0.26, 0.13), 1.0),
        depth: Depth.readWrite(),
        blend: Blend.alpha()
      },
      (pass): void => {
        drawSimpleModelBatch(pass, renderScene.placeholders)
      },
    )
    renderer.pass(
      RenderPassDescriptor {
        camera,
        depth: Depth.readWrite(),
        blend: Blend.alpha(),
        cull: CullMode.Back
      },
      (pass): void => {
        drawSimpleModelBatch(pass, renderScene.backs)
      },
    )
    renderer.pass(
      RenderPassDescriptor {
        camera,
        depth: Depth.readWrite(),
        blend: Blend.alpha(),
        cull: CullMode.Back
      },
      (pass): void => {
        drawSimpleModelBatch(pass, renderScene.fronts)
      },
    )
    renderer.pass(
      RenderPassDescriptor {
        camera: Camera.screen(),
        depth: Depth.disabled(),
        blend: Blend.alpha(),
      },
      (pass): void => {
        drawSimpleMesh(pass, createRestartButtonMesh(app.surface, restartButton))
      },
    )
    if animating || buttonAnimating || cameraMoving {
      app.requestRender()
    }
  })

  app.requestRender()

  return app.run()
}

export function main(): int {
  result := runSolitaire()
  case result {
    s: Success -> return 0
    f: Failure -> {
      println(f.error)
      return 1
    }
  }
}
