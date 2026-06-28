// Application state — wraps all game objects into a single root.

import { Card, PlayingCard } from "./cards"
import { Pile, SolitaireState, initializeGame, updateCardPositions } from "./game"
import { updateAnimations, attemptAutoMove, checkWin } from "./rules"
import {
  handleClick, handleDragStart, handleDragMove, handleDragEnd, cancelSelection
} from "./input"

export class AppState {
  state: SolitaireState
  undoHistory: SolitaireState[] = []
}

function cloneCard(card: Card): Card {
  return Card {
    cardId: card.cardId,
    x: card.x,
    z: card.z,
    y: card.y,
    width: card.width,
    height: card.height,
    faceUp: card.faceUp,
    currentLift: card.currentLift,
    currentRotation: card.currentRotation,
    flipPhase: card.flipPhase,
    flipProgress: card.flipProgress,
    flipLiftHeight: card.flipLiftHeight,
    flipDuration: card.flipDuration,
    flipTargetFaceUp: card.flipTargetFaceUp,
  }
}

function cloneCardInfo(card: PlayingCard): PlayingCard {
  return PlayingCard {
    suit: card.suit,
    rank: card.rank,
  }
}

function clonePile(pile: Pile): Pile {
  return Pile {
    cardIndices: pile.cardIndices.cloneMutable(),
    firstFaceUpIndex: pile.firstFaceUpIndex,
    x: pile.x,
    z: pile.z,
  }
}

function cloneSolitaireState(state: SolitaireState): SolitaireState {
  cards: Card[] := []
  for card of state.cards {
    cards.push(cloneCard(card))
  }

  cardInfo: PlayingCard[] := []
  for info of state.cardInfo {
    cardInfo.push(cloneCardInfo(info))
  }

  copy := SolitaireState {
    cards,
    cardInfo,
    tableau0: clonePile(state.tableau0),
    tableau1: clonePile(state.tableau1),
    tableau2: clonePile(state.tableau2),
    tableau3: clonePile(state.tableau3),
    tableau4: clonePile(state.tableau4),
    tableau5: clonePile(state.tableau5),
    tableau6: clonePile(state.tableau6),
    foundations: {
      .Spades: clonePile(state.foundation(0)),
      .Hearts: clonePile(state.foundation(1)),
      .Diamonds: clonePile(state.foundation(2)),
      .Clubs: clonePile(state.foundation(3)),
    },
    stock: clonePile(state.stock),
    waste: clonePile(state.waste),
  }

  return copy
}

function clearInteractionAndAnimations(state: SolitaireState): void {
  state.selectedPileType = -1
  state.selectedPileIndex = -1
  state.selectedCardIndex = -1
  state.isDragging = false
  state.dealAnimActive = false
  state.dealCardIndex = -1
  state.dealProgress = 0.0f
  state.moveAnimActive = false
  state.moveCardIndex = -1
  state.moveProgress = 0.0f

  for card of state.cards {
    card.y = 0.0f
    card.currentLift = 0.0f
    card.flipPhase = 0
    card.flipProgress = 0.0f
    card.currentRotation = if card.faceUp then 0.0f else 3.14159265358979323846f
  }
}

function pushUndoSnapshot(app: AppState): void {
  app.undoHistory.push(cloneSolitaireState(app.state))
}

// Create a fully initialized application.
export function createApp(): AppState {
  state := SolitaireState {}
  initializeGame(state)

  return AppState {
    state: state
  }
}

// Start a new game, preserving camera and card library.
export function appNewGame(app: AppState): void {
  app.state = SolitaireState {}
  app.undoHistory = []
  initializeGame(app.state)
}

export function appCanUndo(app: AppState): bool {
  return app.undoHistory.length > 0
}

export function appUndo(app: AppState): bool {
  if app.undoHistory.length == 0 { return false }

  previous := app.undoHistory[app.undoHistory.length - 1]
  app.undoHistory = app.undoHistory.slice(0, app.undoHistory.length - 1)
  app.state = cloneSolitaireState(previous)
  clearInteractionAndAnimations(app.state)
  updateCardPositions(app.state)
  return true
}

// Advance animations. Returns true if still animating.
export function appUpdate(app: AppState, deltaTime: float): bool {
  return updateAnimations(app.state, deltaTime)
}

export function appClick(app: AppState, worldX: float, worldZ: float): bool {
  pushUndoSnapshot(app)
  if handleClick(app.state, worldX, worldZ) {
    return true
  }
  app.undoHistory = app.undoHistory.slice(0, app.undoHistory.length - 1)
  return false
}

export function appDragStart(app: AppState, worldX: float, worldZ: float): void {
  handleDragStart(app.state, worldX, worldZ)
}

export function appDragMove(app: AppState, worldX: float, worldZ: float): void {
  handleDragMove(app.state, worldX, worldZ)
}

export function appDragEnd(app: AppState, worldX: float, worldZ: float): bool {
  pushUndoSnapshot(app)
  if handleDragEnd(app.state, worldX, worldZ) {
    return true
  }
  app.undoHistory = app.undoHistory.slice(0, app.undoHistory.length - 1)
  return false
}

export function appCancelInteraction(app: AppState): bool {
  if !app.state.isDragging && app.state.selectedPileType < 0 {
    return false
  }

  updateCardPositions(app.state)
  cancelSelection(app.state)
  return true
}

export function appAutoComplete(app: AppState): bool {
  pushUndoSnapshot(app)
  if attemptAutoMove(app.state) {
    return true
  }
  app.undoHistory = app.undoHistory.slice(0, app.undoHistory.length - 1)
  return false
}

export function appIsWon(app: AppState): bool {
  return checkWin(app.state)
}
