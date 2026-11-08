import '../json.dart';

/// Weights of the suggester's score terms (each term is 0..1).
final class SuggesterWeights {
  const SuggesterWeights({
    this.urgency = 0.30,
    this.neglect = 0.25,
    this.fit = 0.20,
    this.timeOfDay = 0.15,
    this.energyMatch = 0.10,
    this.skipPenalty = 0.30,
  });

  factory SuggesterWeights.fromJson(Json json) => SuggesterWeights(
    urgency: json.reqDouble('urgency'),
    neglect: json.reqDouble('neglect'),
    fit: json.reqDouble('fit'),
    timeOfDay: json.reqDouble('timeOfDay'),
    energyMatch: json.reqDouble('energyMatch'),
    skipPenalty: json.reqDouble('skipPenalty'),
  );

  final double urgency;
  final double neglect;
  final double fit;
  final double timeOfDay;
  final double energyMatch;

  /// Subtracted once per skip of the same activity in the last 24 h.
  final double skipPenalty;

  Json toJson() => {
    'urgency': urgency,
    'neglect': neglect,
    'fit': fit,
    'timeOfDay': timeOfDay,
    'energyMatch': energyMatch,
    'skipPenalty': skipPenalty,
  };

  @override
  bool operator ==(Object other) =>
      other is SuggesterWeights &&
      other.urgency == urgency &&
      other.neglect == neglect &&
      other.fit == fit &&
      other.timeOfDay == timeOfDay &&
      other.energyMatch == energyMatch &&
      other.skipPenalty == skipPenalty;

  @override
  int get hashCode =>
      Object.hash(urgency, neglect, fit, timeOfDay, energyMatch, skipPenalty);
}
