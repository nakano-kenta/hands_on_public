# How to setup
```
brew install sdl2
bundle install
```

# How to play
```
RUBYLIB=lib bundle exec ./bin/rrobots --resolution=1500,1500 tanks/simple.rb tanks/simple.rb
```

# Based on
https://github.com/logankoester/rrobots

# Study
`Win means at least 9 wins in 10 battles !!`

## Entry level (700x700)
1. Win against Simple
   Need to turn gun effectively.
2. Win against Shooter
   Need move to avoid getting hit.
3. Win against Shooter
   Need move to avoid getting hit.

## Basic level(700x700)
10. Win against Aiming
   Need move complicatedly.
11. Win against Wall
   Need to aim uniform speed liner moving targets.
12. Win against Circle
   Need to aim uniform acceleration moving targets.
13. Win against Swing
   Need to aim patterned moving targets.

## Advansed level(700x700)
20. Win against WallShooter
21. Win against CircleShooter
22. Win against SwingShooter

## Master1(1000x1000)
23. Win against WallShooter, CircleShooter and SwingShooter

## Master2(700x700)
31. Win against WallWithAiming
32. Win against CircleWithAiming
33. Win against SiwingWithAiming

## Master3(1000x1000)
34. Win against WallWithAiming, CircleWithAiming and SwingWithAiming

## Master4(700x700)
50. Win against RandomShooter

## Hell(1500x1500) (勝てるもんなら勝ってみろ！！)
777. Win against Kubota
