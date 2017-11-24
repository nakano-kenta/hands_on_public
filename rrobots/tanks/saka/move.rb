require 'rrobots'
require "#{File.dirname(__FILE__)}/utility"
require "#{File.dirname(__FILE__)}/history"

module SakaUtil

  class MoveStrategy
    attr_accessor :next_x, :next_y, :next_speed, :next_heading

    def move(robot)
      @robot = robot
      @next_x = robot.x
      @next_y = robot.y
      @next_heading = robot.heading
      @next_speed = robot.speed
      @next_history = robot.next_history 1
    end
  end

end