module WallUtil
  ON_THE_WALL = 3
  def move_to_coner(angle, &distance_from_wall)
    if heading == angle
      accelerate 1
      distance = distance_from_wall.call
      if distance <= ON_THE_WALL
        accelerate -speed
      elsif distance < 49 and speed != 0
        accelerate 0
        if distance < (speed * (1 + (speed - 1) / 2) + 8.0)
          accelerate -1
        end
        if speed <= 1 and distance > 2
          accelerate 0
        end
      end
    else
      accelerate -speed
      turn_angle = (angle - heading + 360) % 360
      turn_angle -= 360 if turn_angle > 180
      turn turn_angle
    end
  end

  def wall_move
    if x <= @size + ON_THE_WALL and y <= @size + ON_THE_WALL
      move_to_coner 0 do
        battlefield_width - @size - x
      end
    elsif y <= @size + ON_THE_WALL and x >= battlefield_width - @size - ON_THE_WALL
      move_to_coner 270 do
        battlefield_height - @size - y
      end
    elsif y >= battlefield_height - @size - ON_THE_WALL and x <= @size + ON_THE_WALL
      move_to_coner 90 do
        y - @size
      end
    elsif y >= battlefield_height - @size - ON_THE_WALL and x >= battlefield_width - @size - ON_THE_WALL
      move_to_coner 180 do
        x - @size
      end
    elsif y <= @size + ON_THE_WALL
      move_to_coner 0 do
        battlefield_width - @size - x
      end
    elsif x >= battlefield_width - @size - ON_THE_WALL
      move_to_coner 270 do
        battlefield_height - @size - y
      end
    elsif y >= battlefield_height - @size - ON_THE_WALL
      move_to_coner 180 do
        x - @size
      end
    else
      move_to_coner 90 do
        y - @size
      end
    end
  end
end
