require 'rrobots'

module SakaUtil
  module Utility
    private

    def normalize_rotation(rotation)
      rotation = rotation.remainder(360)
      return -(360 - rotation) if rotation > 180
      return 360 + rotation if rotation < -180
      rotation
    end

    def to_angle(radian)
      (radian * 180.0 / Math::PI + 360 * 10000) % 360
    end

    def to_direction(a, b)
      diff_x = a[:x] - b[:x]
      diff_y = b[:y] - a[:y]
      to_angle(Math.atan2(diff_y, diff_x) - Math::PI)
    end
    def trace(message)
      method_name = caller_locations(1,1)[0].label
      puts "#{method_name}: #{message}"
    end
    def debug_draw(x, y, size)
      scale = 0.5
      x *= scale
      y *= scale
      size *= scale
      Gosu.draw_rect(x - size / 2, y - size/ 2, size, size, 0xffffff00, ZOrder::UI + 1)
    end
  end
end
class Saka
  include Robot
  include SakaUtil::Utility

  class History
    attr_accessor :x, :y, :energy, :fired
    def initialize(robot = {}, x = 0.0, y = 0.0)
      @energy = robot[:energy]
      @x, @y = x, y
      @fired = false
    end
    def empty?
      return @x.nil?
    end
    def distance_from(from)
      Math.hypot(self.x - from.x, self.y - from.y)
    end
    def [](key)
      return @x if key == :x
      return @y if key == :y
      return @energy if key == :energy
      nil
    end
  end

  class DiffList
    include SakaUtil::Utility
    def self.from_history(histories)
      DiffList.new(histories, true)
    end
    def append(depth)
      return if depth <= 0 or @list.size < 2 or is_approx_empty?(0.01)
      list = []
      @list.inject do |prev, cur|
        list << create_diff(prev, cur)
        cur
      end
      @parent = DiffList.new list
      @parent.append(depth - 1)
    end
    def next(x, y)
      diff = next_diff
      commit_next diff
      {
        x: diff[:x] + x,
        y: diff[:y] + y
      }
    end

    def next_diff
      ret = @parent&.next_diff || {x: 0, y: 0}
      ret[:x] += @list.first[:x]
      ret[:y] += @list.first[:y]
      ret
    end

    def commit_next(diff)
      parent_diff = {
        x: diff[:x] - @list.first[:x],
        y: diff[:y] - @list.first[:y]
      }
      @list.insert(0, diff)
      @parent&.commit_next parent_diff
    end

    private
    def is_approx_empty?(diff)
      @list.inject do |prev, cur|
        diff_x, diff_y = prev[:x] - cur[:x], prev[:y] - cur[:y]
        if diff_x.abs > diff or diff_y.abs > diff
          return false
        end
        cur
      end
      return true
    end
    def create_diff(to, from)
      to_x, to_y = to[:x], to[:y]
      from_x, from_y = from[:x], from[:y]
      move_x, move_y = to_x - from_x, to_y - from_y
      {
        x: move_x,
        y: move_y,
        speed: Math.hypot(move_x, move_y),
        direction: to_direction(from, to)
      }
    end
    def initialize(listOrHistory, is_history = false)
      @list = listOrHistory
      return unless is_history
      @list = []
      listOrHistory.reverse.inject do |prev, cur|
        break if @list.size > 20 or cur.nil?
        @list << create_diff(prev, cur)
        cur
      end
    end
  end

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

  def tick events
    return if process_scanned events['robot_scanned']
    @histories = nil
    turn_gun MAX_GUN_ROTATE
    turn_radar MAX_RADAR_ROTATE - MAX_GUN_ROTATE
  end
=begin
  @events['robot_scanned'] << {
    distance: Math.hypot(@y - other.y, other.x - @x),
    direction: to_direction({x: @x, y: @y}, {x: other.x, y: other.y}),
    energy: other.energy,
    name: other.name
  }
=end
  def next_history(generation)
    return @histories[generation - 1] if generation <= 0
    # return @histories.last
    return @histories.last if @histories.size <= 1
    @next_histories ||= []
    return @next_histories[generation - 1] if generation <= @next_histories.size
    diff = DiffList.from_history(@histories)
    diff.append(5)
    generation = [@next_histories.size + @next_histories.size / 2, generation].max
    @next_histories.clear
    last_history = @histories.last
    generation.times do |index|
      next_pos = diff.next(last_history.x, last_history.y)
      if next_pos[:x] < size / 2 || next_pos[:x] > (battlefield_width - size / 2) || \
        next_pos[:y] < size / 2 || next_pos[:y] > (battlefield_height - size / 2)
        break
      end
      last_history = History.new({}, next_pos[:x], next_pos[:y])
      @next_histories << last_history
    end
    while @next_histories.size < generation
      @next_histories << last_history
    end
    return @next_histories[generation - 1]
  end
private
  MAX_HISTORIES = 30
  MAX_FIRE = 3
  BULLET_SPEED = 30
  MAX_GUN_ROTATE = 30
  MAX_RADAR_ROTATE = 60
  MAX_BODY_ROTATE = 10
  MAX_SPEED = 8

  def process_scanned(robots)
    return false if robots.empty?
    robot = robots[0]

    history = add_current_history(robot)
    @next_histories = nil
    next_history 20
    try_fire()
    new_state = move()
    adjust_gun_heading(new_state)
    adjust_radar_heading(new_state)

    true
  end
  def add_current_history(robot)
    new_x = Math::cos(robot[:direction].to_rad) * robot[:distance] + x
    new_y = -Math::sin(robot[:direction].to_rad) * robot[:distance] + y
    history = History.new(robot, new_x, new_y)
    @histories ||= []
    @histories.delete_at(-1) if @histories.last&.empty?
    @histories << history
    if @histories.size > MAX_HISTORIES
      @histories.delete_at(0)
    end
    # puts "pos = #{new_x}, #{new_y}"
    # debug_draw(new_x, new_y, size)
    history
  end
  def move
    new_x = self.x
    new_y = self.y
    new_heading = self.heading
    new_speed = self.speed

    history = next_history 1
    target_direction = to_direction({x: self.x, y: self.y}, history)
    desired_rotation = normalize_rotation(target_direction - self.heading)
    adjusted_rotation = desired_rotation
    if adjusted_rotation.abs >= MAX_BODY_ROTATE
      adjusted_rotation = adjusted_rotation > 0 ? MAX_BODY_ROTATE : -MAX_BODY_ROTATE
    end
    accel = 0
    if desired_rotation.abs >= 90
      accel = -1 if new_speed > 0
    elsif desired_rotation.abs <= MAX_BODY_ROTATE * 2
      accel = 1 if new_speed < MAX_SPEED
    end
    new_heading = self.heading + adjusted_rotation
    new_speed = self.speed + accel


    turn(adjusted_rotation)
    accelerate accel if accel.abs > 0

    new_heading = self.heading + adjusted_rotation
    new_speed = self.speed + accel
    new_x = Math::cos(new_heading.to_rad) * new_speed + self.x
    new_y = -Math::sin(new_heading.to_rad) * new_speed + self.y
    {
      x: new_x,
      y: new_y,
      speed: new_speed,
      heading: new_heading,
      gun_heading: self.gun_heading,
      radar_heading: self.radar_heading
    }
  end
  def adjust_gun_heading(new_state)
    bullet_distance = BULLET_SPEED
    generation = 1
    loop do
      history = next_history generation
      if history.distance_from(self) <= bullet_distance
        target_direction = to_direction(new_state, history)
        gun_rotation = normalize_rotation(target_direction - self.gun_heading)
        if gun_rotation.abs >= MAX_GUN_ROTATE
          gun_rotation = gun_rotation > 0 ? MAX_GUN_ROTATE : -MAX_GUN_ROTATE
        end
        turn_gun(gun_rotation)
        new_state[:gun_heading] = self.gun_heading + gun_rotation
        break
      end
      bullet_distance += BULLET_SPEED
      generation += 1
    end
  end
  def adjust_radar_heading(new_state)
    history = next_history 1
    target_direction = to_direction(new_state, history)
    radar_rotation = normalize_rotation(target_direction - self.radar_heading)
    if radar_rotation.abs <= (MAX_RADAR_ROTATE / 2)
       radar_rotation = radar_rotation + (radar_rotation > 0 ? MAX_RADAR_ROTATE / 2 : -MAX_RADAR_ROTATE / 2)
    else
      radar_rotation = radar_rotation > 0 ? MAX_RADAR_ROTATE : -MAX_RADAR_ROTATE
    end
    turn_radar(radar_rotation)
    new_state[:radar_heading] = self.radar_heading + radar_rotation
  end
  def try_fire
    return false if gun_heat > 0
    bullet_distance = BULLET_SPEED
    generation = 1
    loop do
      history = next_history generation
      if history.distance_from(self) <= bullet_distance
        target_directions = []
        from = {x: self.x, y: self.y}
        target_directions << to_direction(from, {x: history.x - size / 2, y: history.y - size / 2})
        target_directions << to_direction(from, {x: history.x + size / 2, y: history.y - size / 2})
        target_directions << to_direction(from, {x: history.x - size / 2, y: history.y + size / 2})
        target_directions << to_direction(from, {x: history.x + size / 2, y: history.y + size / 2})
        target_directions.sort!()
        return false if self.gun_heading <= target_directions[0] or self.gun_heading >= target_directions[-1]

        diff_from_target = self.gun_heading - to_direction(from, history)
        target_range = target_directions[-1] - target_directions[0]
        possibility = (target_range / 2 - diff_from_target.abs) / (target_range / 2)
        if bullet_distance < size * 2
          possibility = 1
        elsif bullet_distance < size * 4
          possibility = [possibility * 3, 1].min
        elsif bullet_distance < size * 8
          possibility = [possibility * 2, 1].min
        end
        fire possibility * MAX_FIRE
        return true
      end
      bullet_distance += BULLET_SPEED
      generation += 1
    end
  end
end
