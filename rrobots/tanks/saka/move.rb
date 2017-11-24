require 'rrobots'
require "#{File.dirname(__FILE__)}/utility"
require "#{File.dirname(__FILE__)}/history"

module SakaUtil

  class MoveStrategy
    include SakaUtil::Utility
    include SakaUtil::Constants

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
      @next_x = Math::cos(@next_heading.to_rad) * @next_speed + @owner.x
      @next_y = -Math::sin(@next_heading.to_rad) * @next_speed + @owner.y
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
end