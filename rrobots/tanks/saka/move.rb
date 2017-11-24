require 'rrobots'
require "#{File.dirname(__FILE__)}/utility"
require "#{File.dirname(__FILE__)}/history"
require 'securerandom'

module SakaUtil

  class PositionConverter
    include SakaUtil::Utility
    def convert(pos, ratio)
      pos
    end
  end

  class Bezier2PositionConverter < PositionConverter
    def initialize(from, to)
      @from = from
      @to = to
      @pos1 = {
        x: SecureRandom.random_number,
        y: SecureRandom.random_number
      }
    end
    def convert(pos, ratio)
      return pos if ratio <= 0 or ratio >= 1

      ratio_x = 2*(1-ratio)*ratio*@pos1[:x] + ratio*ratio
      ratio_y = 2*(1-ratio)*ratio*@pos1[:y] + ratio*ratio
      {
        x: (pos[:x] - @from[:x]) * (ratio_x / ratio) + @from[:x],
        y: (pos[:y] - @from[:y]) * (ratio_y / ratio) + @from[:y]
      }
    end
  end

  class MoveStrategy
    include SakaUtil::Utility
    include SakaUtil::Constants

    DEBUG = false

    attr_accessor :next_x, :next_y, :next_speed, :next_heading, :rotation, :accelerate, :target

    def initialize(owner, target)
      @owner = owner
      @target = target
    end

    def move
      false
    end

    def apply
      @owner.turn(@rotation)
      @owner.accelerate(@accelerate) if @accelerate.abs > 0
    end

    private
    def finish(rotation, accel)
      @rotation = rotation
      @accelerate = accel

      @next_heading = @owner.heading + @rotation
      @next_speed = @owner.speed + @accelerate
      @next_x = calc_x(@next_heading, @next_speed)
      @next_y = calc_y(@next_heading, @next_speed)
    end

    def calc_x(direction, speed)
      Math::cos(direction.to_rad) * speed + @owner.x
    end

    def calc_y(direction, speed)
      -Math::sin(direction.to_rad) * speed + @owner.y
    end

    def round_x(x)
      padding = @owner.size / 2
      if x < padding
        @owner.size / 2
      elsif x > (@owner.battlefield_width - padding)
        @owner.battlefield_width - padding
      else
        x
      end
    end
    def round_y(y)
      padding = @owner.size / 2
      if y < padding
        @owner.size / 2
      elsif y > (@owner.battlefield_height - padding)
        @owner.battlefield_height - padding
      else
        y
      end
    end
  end

  class KamikazeMoveStrategy < MoveStrategy
    def move
      history = @target.next 1
      target_direction = to_direction(@owner, history)
      desired_rotation = to_min_direction(target_direction - @owner.heading)
      adjusted_rotation = desired_rotation
      if adjusted_rotation.abs >= MAX_BODY_ROTATE
        adjusted_rotation = adjusted_rotation > 0 ? MAX_BODY_ROTATE : -MAX_BODY_ROTATE
      end
      accel = 0
      if desired_rotation.abs >= 90
        accel = -1 if @owner.speed > 0
      elsif desired_rotation.abs <= MAX_BODY_ROTATE * 2
        accel = 1 if @owner.speed < MAX_SPEED
      end
      finish adjusted_rotation, accel
      true
    end
  end

  class MoveStrategyBase < MoveStrategy
    def initialize(owner, target)
      super
      @next_position = -1
      @max_distance = owner.size * 4
    end

    def move
      if @next_position < 0
        unless setup
          return false
        end
        if DEBUG
          debug_draw_point @to[:x], @to[:y], 1 * @owner.size, 0xff00ffff
        end
      end
      last_pos = {x: @owner.x, y: @owner.y}
      next_pos = nil
      moved = 0
      loop do
        pos = calc_next
        break if !pos or to_distance(pos, @from) > @max_distance
        next_pos = pos
        moved += to_distance(last_pos, next_pos)
        last_pos = next_pos
        @next_position += 1
        break if moved > @owner.speed
      end
      unless next_pos
        if finished
          return move
        else
          return false
        end
      end

      target_direction = to_direction(@owner, next_pos)
      desired_rotation = to_min_direction(target_direction - @owner.heading)
      adjusted_rotation = desired_rotation
      if adjusted_rotation.abs >= MAX_BODY_ROTATE
        adjusted_rotation = adjusted_rotation > 0 ? MAX_BODY_ROTATE : -MAX_BODY_ROTATE
      end
      accel = @owner.speed < MAX_SPEED ? 1 : 0
      finish adjusted_rotation, accel
      true
    end

    def finished
      false
    end

    private
    def convert_position(pos)
      return pos if @position_converter.nil?
      ratio = to_distance(@from, pos) / to_distance(@from, @to)
      new_pos = @position_converter.convert(pos, ratio > 1 ? 1 : ratio)
      new_pos
    end
  end

  class RandomMoveToTargetStrategy < MoveStrategyBase
    attr_reader :max_direction
    def initialize(owner, target, max_direction = 60)
      super(owner, target)
      @max_direction = max_direction
    end

    def calc_next
      pos = {
        x: calc_x(@direction, @next_position),
        y: calc_y(@direction, @next_position)
      }
      convert_position(pos)
    end

    def setup
      @from = {x: @owner.x, y: @owner.y}
      10.times do
        @direction = to_direction(@owner, @target.next(0))
        @direction += (SecureRandom.random_number * 2 - 1.0) * @max_direction

        to_x = round_x calc_x(@direction, @max_distance)
        to_y = round_y calc_y(@direction, @max_distance)
        @to = {x: to_x, y: to_y}
        @next_position = 0
        break if to_distance(@owner, @to) > (@max_distance / 2)
      end
      @position_converter = Bezier2PositionConverter.new(@from, @to)
      true
    end
  end


  class RandomMoveStrategy < MoveStrategyBase
    def initialize(owner)
      super owner, nil
    end
    def calc_next
      pos = {
        x: calc_x(@direction, @next_position),
        y: calc_y(@direction, @next_position)
      }
      convert_position(pos)
    end

    def finished
      setup
      true
    end

    def setup
      @from = {x: @owner.x, y: @owner.y}
      10.times do
        to_x = round_x (SecureRandom.random_number * 2 - 1.0) * @owner.size * 4 + @owner.x
        to_y = round_y (SecureRandom.random_number * 2 - 1.0) * @owner.size * 4 + @owner.y
        @to = {x: to_x, y: to_y}
        @direction = to_direction(@owner, @to)
        @next_position = 0
        break if to_distance(@owner, @to) > @owner.size
      end
      @position_converter = Bezier2PositionConverter.new(@from, @to)
      true
    end
  end
end