require 'rrobots'

module SakaUtil
  module Constants
    MAX_HISTORIES = 100
    MAX_FIRE = 3
    BULLET_SPEED = 30
    MAX_GUN_ROTATE = 30
    MAX_RADAR_ROTATE = 60
    MAX_BODY_ROTATE = 10
    MAX_SPEED = 8
  end
  module Utility
    private

    def normalize_rotation(rotation)
      rotation = (rotation + 360 * 100000) % 360
      rotation < 180 ? rotation : -(360 - rotation)
    end

    def to_angle(radian)
      (radian * 180.0 / Math::PI + 360 * 10000) % 360
    end

    def to_direction(a, b)
      diff_x = a[:x] - b[:x]
      diff_y = b[:y] - a[:y]
      to_angle(Math.atan2(diff_y, diff_x) - Math::PI)
    end

    def to_distance(a, b)
      Math::hypot(a[:x] - b[:x], b[:y] - a[:y])
    end
    def trace(message)
      method_name = caller_locations(1,1)[0].label
      puts "#{method_name}: #{message}"
    end
    def debug_draw(x, y, size, color = 0xffffff00)
      scale = 0.5
      x *= scale
      y *= scale
      size *= scale
      Gosu.draw_rect(x - size / 2, y - size/ 2, size, size, color, ZOrder::UI + 1)
    end

    def nearest_direction(direction, base_direction)
      nearest = direction
      (-10..10).each do |mul|
        alt = direction + mul * 360
        nearest = alt if (alt - base_direction).abs < (nearest - base_direction).abs
      end
      nearest
    end
  end
end
class Saka
  include Robot
  include SakaUtil::Utility
  include SakaUtil::Constants

  DEBUG_FIRE = true

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

  class NextPositionStrategy
    include SakaUtil::Utility
    include SakaUtil::Constants
    def self.from_history(histories)
      strategy = NextPositionStrategy.new(histories, true)
      strategy.append(6)
      strategy
    end
    def append(depth)
      return if depth <= 0 or @list.size < 2 or is_approx_empty?(0.05, 0.5)
      list = []
      @list.inject do |prev, cur|
        list << create_diff(prev, cur, @list.last, false)
        cur
      end
      @parent = NextPositionStrategy.new list
      @parent.append(depth - 1)
    end
    def dump_next
      (1..@next_start).each do |generation|
        history = get_next(generation)
        debug_draw(history[:x] - 2, history[:y] - 2, 5, 0xffffffff)
      end
    end
    def get_next(generation)
      return @list[@next_start - generation] if @next_start >= generation
      (@next_start...generation).each do |i|
        self.add_next
      end
      return @list.first
    end

    def add_next
      vec = get_next_vector
      from = @list.first
      direction = nearest_direction(vec[:direction], from[:direction])
      angle_rad = direction.to_rad
      distance = vec[:speed]
      distance = 0 if distance < 0
      distance = MAX_SPEED if distance > MAX_SPEED
      to = {
        x: Math::cos(angle_rad) * distance + from[:x],
        y: -Math::sin(angle_rad) * distance + from[:y]
      }
      diff = create_diff(to, from, @list.first, true)
      @list.insert(0, diff)
      @next_start += 1
      @parent&.append_next(@list[0], @list[1])
    end

    def get_next_vector(depth = 0)
      my_vec = {
        speed: @list.first[:speed],
        direction: @list.first[:direction]
      }
      if depth > 0
        sub_list = @list.slice(1, depth * 3)
        sub_list.each do |item|
          my_vec[:speed] += item[:speed]
          my_vec[:direction] += item[:direction]
        end
        my_vec[:speed] /= sub_list.size + 1
        my_vec[:direction] /= sub_list.size + 1
      end
      if @parent
        parent_vec = @parent.get_next_vector(depth + 1)
        if parent_vec
          my_vec[:speed] += parent_vec[:speed]
          my_vec[:direction] += parent_vec[:direction]
          return my_vec
        end
      end
      my_vec
    end

    def append_next(to, from)
      @list.insert(0, create_diff(to, from, @list.first,false))
      @next_start += 1
      @parent&.append_next(@list[0], @list[1])
    end

    def reset
      @list.slice!(0, @next_start)
      @next_start = 0
      @parent&.reset
    end

    private
    def is_approx_empty?(speed_diff, direction_diff)
      @list.inject do |prev, cur|
        diff_x, diff_y = prev[:x] - cur[:x], prev[:y] - cur[:y]
        if (prev[:speed] - cur[:speed]).abs > speed_diff \
          or (prev[:direction] - cur[:direction]).abs > direction_diff
          return false
        end
        cur
      end
      return true
    end
    def create_diff(to, from, last_entry, is_root)
      to_x, to_y = to[:x], to[:y]
      from_x, from_y = from[:x], from[:y]
      move_x, move_y = to_x - from_x, to_y - from_y
      if is_root
        direction = to_direction(from, to)
        if last_entry and last_entry[:direction]
          last_direction = last_entry[:direction]
          direction = nearest_direction(direction, last_direction)
        end
      else
        direction = nearest_direction(to[:direction], from[:direction]) - from[:direction]
      end
      {
        x: to_x,
        y: to_y,
        move_x: move_x,
        move_y: move_y,
        speed: is_root ? Math.hypot(move_x, move_y) : (to[:speed] - from[:speed]),
        direction: direction
      }
    end
    def initialize(listOrHistory, is_history = false)
      @list = listOrHistory
      @next_start = 0
      return unless is_history
      @list = []
      listOrHistory.reverse.inject do |prev, cur|
        break if cur.nil?
        @list << create_diff(prev, cur, @list.last, true)
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
  def next_history(generation)
    return @histories[generation - 1] if generation <= 0
    return @histories.last if @histories.size <= 1
    @next_histories ||= NextPositionStrategy.from_history @histories
    next_history = @next_histories.get_next(generation)
    History.new({}, next_history[:x], next_history[:y])
  end
  private

  def process_scanned(robots)
    return false if robots.empty?
    robot = robots[0]

    history = add_current_history(robot)
    @next_histories = nil
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
    history = history_for_bullet
    return false if history.nil?
    target_direction = to_direction(new_state, history)
    gun_rotation = normalize_rotation(target_direction - self.gun_heading)
    if gun_rotation.abs >= MAX_GUN_ROTATE
      gun_rotation = gun_rotation > 0 ? MAX_GUN_ROTATE : -MAX_GUN_ROTATE
    end
    turn_gun(gun_rotation)
    new_state[:gun_heading] = self.gun_heading + gun_rotation
    true
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
  def history_for_bullet
    my_pos = {x: self.x, y: self.y}
    max_distance = [
      to_distance(my_pos, {x: 0, y:0}),
      to_distance(my_pos, {x: battlefield_width, y:0}),
      to_distance(my_pos, {x: battlefield_width, y:battlefield_height}),
      to_distance(my_pos, {x: 0, y:battlefield_height})
    ].sort!.last
    bullet_distance = BULLET_SPEED
    max_generations = (max_distance / BULLET_SPEED).to_i + 1
    (1..max_generations).each do |generation|
      history = next_history generation
      break if history.nil?
      return history if history.distance_from(self) <= bullet_distance
      bullet_distance += BULLET_SPEED
    end
    trace("history_for_bullet : not found max=#{max_generations}")
    nil
  end
  def try_fire
    unless DEBUG_FIRE
      return false if gun_heat > 0
    end
    history = history_for_bullet
    return false if history.nil?

    if DEBUG_FIRE
      @next_histories.dump_next if @next_histories
      dump_target_histories(@histories) if @histories
    end

    bullet_distance = history.distance_from(self)
    target_directions = []
    from = {x: self.x, y: self.y}
    target_directions << to_direction(from, {x: history.x - size / 2, y: history.y - size / 2})
    target_directions << to_direction(from, {x: history.x + size / 2, y: history.y - size / 2})
    target_directions << to_direction(from, {x: history.x - size / 2, y: history.y + size / 2})
    target_directions << to_direction(from, {x: history.x + size / 2, y: history.y + size / 2})
    target_directions.sort!()
    if self.gun_heading <= target_directions.first or self.gun_heading >= target_directions.last
      if DEBUG_FIRE
        debug_draw history.x, history.y, 1 * size, 0xff00ffff
      end
      return false
    end

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
    strength = possibility * MAX_FIRE
    fire strength

    if DEBUG_FIRE
      debug_draw Math::cos(self.gun_heading.to_rad) * history.distance_from(self) + x, -Math::sin(self.gun_heading.to_rad) * history.distance_from(self) + y, strength * size
    end
    true
  end
  def dump_target_histories(histories)
    histories.each do |history|
      debug_draw(history[:x] - 2, history[:y] - 2, 5, 0xffff0000)
    end
  end
end
