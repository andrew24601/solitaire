export enum Suit { Spades = 0, Hearts = 1, Diamonds = 2, Clubs = 3 }

export enum Rank {
  Ace = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7,
  Eight = 8, Nine = 9, Ten = 10, Jack = 11, Queen = 12, King = 13
}

export struct PlayingCard {
  readonly suit: Suit = .Spades
  readonly rank: Rank = .Ace

  isRed(): bool => suit == .Hearts || suit == .Diamonds
  isBlack(): bool => suit == .Spades || suit == .Clubs
  rankValue(): int => rank.value
}

export class Card {
  cardId: string = ""
  let x: float = 0.0f
  let z: float = 0.0f
  let y: float = 0.0f
  width: float = 80.0f
  height: float = 120.0f
  let faceUp: bool = true
  let currentLift: float = 0.0f
  let currentRotation: float = 0.0f

  let flipPhase: int = 0
  let flipProgress: float = 0.0f
  flipLiftHeight: float = 80.0f
  flipDuration: float = 0.38f
  let flipTargetFaceUp: bool = true
}

export function createDeck(): PlayingCard[] {
  cards: PlayingCard[] := []
  suits: Suit[] := [.Spades, .Hearts, .Diamonds, .Clubs]
  ranks: Rank[] := [
    .Ace, .Two, .Three, .Four, .Five, .Six,
    .Seven, .Eight, .Nine, .Ten, .Jack, .Queen, .King
  ]

  for s of 0..3 {
    for r of 0..12 {
      cards.push(PlayingCard { suit: suits[s], rank: ranks[r] })
    }
  }

  return cards
}

export function cardId(suit: Suit, rank: Rank): string {
  return `card_${suit.value}_${rank.value}`
}

export function cardBackId(): string => "card_back"

export function foundationSuit(index: int): Suit {
  return Suit.fromValue(index) ?? .Spades
}
