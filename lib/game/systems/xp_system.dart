class XpSystem {
  int currentLevel = 1;
  int currentXp = 0;

  int get xpToNextLevel => _threshold(currentLevel);

  double get xpFraction =>
      (currentXp / xpToNextLevel).clamp(0.0, 1.0);

  static int _threshold(int level) {
    double xp = 50;
    for (int i = 1; i < level; i++) {
      xp *= 1.5;
    }
    return xp.round();
  }

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
