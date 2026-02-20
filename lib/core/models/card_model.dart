import 'package:flutter/material.dart' show Color;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../theme/app_colors.dart';

part 'card_model.freezed.dart';
part 'card_model.g.dart';

// ── Enumerations ──────────────────────────────────────────────────────────────

enum Suit {
  spades,
  clubs,
  hearts,
  diamonds;

  bool get isBlack => this == Suit.spades || this == Suit.clubs;
  bool get isRed => this == Suit.hearts || this == Suit.diamonds;

  String get symbol => switch (this) {
        Suit.spades => '♠',
        Suit.clubs => '♣',
        Suit.hearts => '♥',
        Suit.diamonds => '♦',
      };

  String get displayName => switch (this) {
        Suit.spades => 'Spades',
        Suit.clubs => 'Clubs',
        Suit.hearts => 'Hearts',
        Suit.diamonds => 'Diamonds',
      };
}

enum Rank {
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
  ace,
  joker;

  /// Numeric value used for sequence comparisons (Numerical Flow rule).
  int get numericValue => switch (this) {
        Rank.two => 2,
        Rank.three => 3,
        Rank.four => 4,
        Rank.five => 5,
        Rank.six => 6,
        Rank.seven => 7,
        Rank.eight => 8,
        Rank.nine => 9,
        Rank.ten => 10,
        Rank.jack => 11,
        Rank.queen => 12,
        Rank.king => 13,
        Rank.ace => 14,
        Rank.joker => 0,
      };

  String get displayLabel => switch (this) {
        Rank.two => '2',
        Rank.three => '3',
        Rank.four => '4',
        Rank.five => '5',
        Rank.six => '6',
        Rank.seven => '7',
        Rank.eight => '8',
        Rank.nine => '9',
        Rank.ten => '10',
        Rank.jack => 'J',
        Rank.queen => 'Q',
        Rank.king => 'K',
        Rank.ace => 'A',
        Rank.joker => '🃏',
      };
}

// ── Model ─────────────────────────────────────────────────────────────────────

@freezed
class CardModel with _$CardModel {
  const factory CardModel({
    required String id,
    required Rank rank,
    required Suit suit,

    /// Only set when this card is a Joker that has been declared by the player.
    Suit? jokerDeclaredSuit,
    Rank? jokerDeclaredRank,
  }) = _CardModel;

  factory CardModel.fromJson(Map<String, dynamic> json) =>
      _$CardModelFromJson(json);
}

// ── Extensions ────────────────────────────────────────────────────────────────

extension CardModelX on CardModel {
  bool get isJoker => rank == Rank.joker;
  bool get isBlackJack =>
      rank == Rank.jack && (suit == Suit.spades || suit == Suit.clubs);
  bool get isRedJack =>
      rank == Rank.jack && (suit == Suit.hearts || suit == Suit.diamonds);
  bool get isSpecial => switch (rank) {
        Rank.two ||
        Rank.jack ||
        Rank.queen ||
        Rank.king ||
        Rank.ace ||
        Rank.eight ||
        Rank.joker =>
          true,
        _ => false,
      };

  /// The effective suit to use for matching (Joker uses declared suit).
  Suit get effectiveSuit => isJoker ? (jokerDeclaredSuit ?? suit) : suit;

  /// The effective rank to use for matching (Joker uses declared rank).
  Rank get effectiveRank => isJoker ? (jokerDeclaredRank ?? rank) : rank;

  /// Card face color from the design spec.
  Color get suitColor =>
      suit.isRed ? AppColors.suitRed : AppColors.suitBlack;

  String get shortLabel => '${rank.displayLabel}${suit.symbol}';
}
