class Saka
  include Robot

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

  def tick events
    return if process_scanned events['robot_scanned']
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
private
  MAX_HISTORIES = 100
  MAX_FIRE = 3
  BULLET_SPEED = 30
  MAX_GUN_ROTATE = 30
  MAX_RADAR_ROTATE = 60

  def process_scanned(robots)
    return false if robots.empty?
    robot = robots[0]

    history = add_current_history(robot)
    @next_histories = nil
    try_fire()
    new_state = move()
    adjust_gun_heading(new_state)
    adjust_radar_heading(new_state)

    # debug_draw(new_x, new_y, size)
    true
  end
  def add_current_history(robot)
    new_x = Math::cos(to_radian(robot[:direction])) * robot[:distance] + x
    new_y = -Math::sin(to_radian(robot[:direction])) * robot[:distance] + y
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
    {
      x: self.x,
      y: self.y,
      heading: self.heading,
      gun_heading: self.gun_heading
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
  def normalize_rotation(rotation)
    rotation = rotation.remainder(360)
    return 360 - rotation if rotation > 180
    return 360 + rotation if rotation < -180
    rotation
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
        if bullet_distance < size
          possibility = 1
        end
        fire possibility * MAX_FIRE
        return true
      end
      bullet_distance += BULLET_SPEED
      generation += 1
    end
  end
  def next_history(generation)
    return @histories[generation - 1] if generation <= 0
    # TODO guess
    return @histories.last
  end
  def to_radian(degree)
    degree * Math::PI / 180
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
  def to_angle(radian)
    (radian * 180.0 / Math::PI + 360) % 360
  end

  def to_direction(a, b)
    diff_x = a[:x] - b[:x]
    diff_y = b[:y] - a[:y]
    to_angle(Math.atan2(diff_y, diff_x) - Math::PI)
  end
end