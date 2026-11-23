/// Ground Assault's levels (the designer owns this file; format in
/// README.md). Keep [assaultLevels] and each entry's (name, rows) shape;
/// every row the same length, exactly 13 rows.
///
/// Stage 1, "Crash Site" (292 tiles): you start beside your wrecked lander
/// and fight east to the ship. Beat by beat (columns):
///   0-23    landing zone: run, hop a one-tile step, jump a 2-wide pit
///           (a shard hangs over it for a full jump)
///   24-37   first grunt, alone, on flat ground (auto-fire does the work)
///   38-45   Spread capsule on a low ledge, before the first real fight
///   46-58   first runner, alone (a charger: stand and shoot, or jump it)
///   61      checkpoint 1
///   64-80   first turret, alone, on a rock two tiles up; a ledge puts you
///           level with it; a shard tucked behind the rock
///   81-96   first flyer, alone, over open ground
///   97-120  first mix: grunt, a 3-wide pit (shard over it), runner,
///           grunt, a flyer above
///   123     Laser capsule on a ledge; 129 checkpoint 2
///   132-197 set piece: Bunker Hill (terraces climbing two rows at a time,
///           a grunt on each, a turret and a flyer on top, a shard under
///           the turret) then the Ravine: a 30-wide drop crossed on rock
///           islands and one-way platforms with flyers swooping, a high
///           road with a shard, and a turret on the far cliff
///   198-226 the gauntlet: spike beds, grunts and runners together, a
///           flyer, a shard between two spike beds
///   231     Rockets capsule (for the boss); 237 checkpoint 3; a short
///           climb with a shard
///   248-273 mini-boss arena: flat floor, two low dodge ledges inside the
///           locked view (258.5-268.5)
///   274-291 the ship (E at 286)
/// Checked with a replay of the pilot's physics (jump 2.9 tiles, run 6
/// tiles/s): every gap is 2-3 tiles (max 4), every climb at most 2 rows,
/// all 7 shards and the ship are reachable, rows 0-3 stay sky.
library;

class AssaultLevelSource {
  final String name;
  final List<String> rows;
  const AssaultLevelSource(this.name, this.rows);
}

const assaultLevels = [
  AssaultLevelSource('Crash Site', [
    '                                                                                                                                                                                                                                                                                                    ',
    '                                                                                                                                                                                                                                                                                                    ',
    '                                                                                                                                                                                                                                                                                                    ',
    '                                                                                                                                                                                                                                                                                                    ',
    '                                                                                                                                                       f                                f                                                                                                           ',
    '                                                                                                                                                                          f        *                                    f                                                                           ',
    '                                                                                           f                    f                                  g    *  t                      ===                                                                *                                              ',
    '                                                                                                                                                ##############                                                                                      ==                                              ',
    '                 *                       S                                t                               *                L                 g  ##############   ###   ===        ===  ###         t                          g        R                                                            ',
    '                                        ===                        ===  ####                                              ===             ####################   ###         ###       ###  ##########                      ####      ===        ===               ==  ==                           ',
    '   P       #####                 g                      r    K          #### *                         g            r  g         K     r  ####################               ###            ##########     ^^  g   ^^^*   r #### r           K                            B                   E     ',
    '################  #######################################################################################   ##################################################                              ########################################################################################################',
    '################  #######################################################################################   ##################################################                              ########################################################################################################',
  ]),
];
