class XpSystem {
  int currentLevel = 1;
  int currentXp = 0;

  int get xpToNextLevel => _threshold(currentLevel);

  double get xpFraction =>
      (currentXp / xpToNextLevel).clamp(0.0, 1.0);

  static int _threshold(int level) => 60 + 40 * level;

  // Returns true if a level-up occurred.
  bool addXp(int xp) {
    currentXp += xp;
    if (currentXp >= xpToNextLevel) {
      currentXp -= xpToNextLevel;
      currentLevel++;
      return true;
    }
    return false;
  }

  void reset() {
    currentLevel = 1;
    currentXp = 0;
  }
}
