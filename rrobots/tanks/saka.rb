require 'rrobots'
require "#{File.dirname(__FILE__)}/saka/utility"
require "#{File.dirname(__FILE__)}/saka/history"
require "#{File.dirname(__FILE__)}/saka/move"

class Saka
  include Robot
  include SakaUtil::Utility
  include SakaUtil::Constants

  DEBUG_FIRE = false

  def initialize
    @target_histories = {}
    @move_strategy = nil
  end

  def [](key)
    return @x if key == :x
    return @y if key == :y
    nil
  end

  def tick events
    return if num_robots <= 1
    return if process_scanned events['robot_scanned']
    @move_strategy = SakaUtil::RandomMoveStrategy.new(self) unless @move_strategy.is_a?(SakaUtil::RandomMoveStrategy)
    @move_strategy.move
    @move_strategy.apply
    turn_gun MAX_GUN_ROTATE
    turn_radar MAX_RADAR_ROTATE
  end

  private
  def process_scanned(robots)
    @target_histories.each_value do |target_history|
      target_history.selected = false
    end
    robots.each do |robot|
      @target_histories[robot[:name]] ||= SakaUtil::TargetHistory.new(self, MAX_HISTORIES)
      target_history = @target_histories[robot[:name]]
      target_history.add(robot)
      target_history.selected = true
    end
    @target_histories.reject! do |name, target_history|
      target_history.add_empty if !target_history.selected? and target_history.empty_count < 3
      rejected = !target_history.selected?
      target_history.selected = false
      rejected
    end
    target = nil
    target_distance = 0
    @target_histories.each_value do |target_history|
      if !target
        target = target_history
        target_distance = to_distance(self,target_history.next(0))
      else
        new_target_distance = to_distance(self,target_history.next(0))
        if new_target_distance < target_distance
          target = target_history
          target_distance = new_target_distance
        end
      end
    end

    return false unless target
    target.selected = true

    try_fire(target)
    new_state = move(target)
    adjust_gun_heading(target, new_state)
    adjust_radar_heading(target, new_state)

    true
  end
  def move target_history
    @move_strategy = nil unless @move_strategy and @move_strategy.target == target_history
    distance_units = to_distance(self, target_history.next(0)) / size
    if distance_units < 2
      @move_strategy = SakaUtil::KamikazeMoveStrategy.new(self, target_history) unless @move_strategy.is_a?(SakaUtil::KamikazeMoveStrategy)
    else
      max_direction = 60
      if distance_units < 5
        max_direction = 30
      elsif distance_units < 10
        max_direction = 45
      end
      if @move_strategy.is_a?(SakaUtil::RandomMoveToTargetStrategy)
        @move_strategy = nil if @move_strategy.max_direction != max_direction
      end
      @move_strategy = SakaUtil::RandomMoveToTargetStrategy.new(self, target_history, max_direction) unless @move_strategy.is_a?(SakaUtil::RandomMoveToTargetStrategy)
    end
    if !@move_strategy.move
      @move_strategy = SakaUtil::RandomMoveToTargetStrategy.new(self, target_history)
      @move_strategy.move
    end
    @move_strategy.apply
    {
      x: @move_strategy.next_x,
      y: @move_strategy.next_y,
      speed: @move_strategy.next_speed,
      heading: @move_strategy.next_heading,
      gun_heading: self.gun_heading,
      radar_heading: self.radar_heading
    }
  end
  def adjust_gun_heading(target_history, new_state)
    history = history_for_bullet target_history
    return false if history.nil?
    target_direction = to_direction(new_state, history)
    gun_rotation = to_min_direction(target_direction - self.gun_heading)
    if gun_rotation.abs >= MAX_GUN_ROTATE
      gun_rotation = gun_rotation > 0 ? MAX_GUN_ROTATE : -MAX_GUN_ROTATE
    end
    turn_gun(gun_rotation)
    new_state[:gun_heading] = self.gun_heading + gun_rotation
    true
  end
  def adjust_radar_heading(target_history, new_state)
    history = target_history.next 1
    target_direction = to_direction(new_state, history)
    radar_rotation = to_min_direction(target_direction - self.radar_heading)
    if radar_rotation.abs <= (MAX_RADAR_ROTATE / 2)
      radar_rotation = radar_rotation + (radar_rotation > 0 ? MAX_RADAR_ROTATE / 2 : -MAX_RADAR_ROTATE / 2)
    else
      radar_rotation = radar_rotation > 0 ? MAX_RADAR_ROTATE : -MAX_RADAR_ROTATE
    end
    turn_radar(radar_rotation)
    new_state[:radar_heading] = self.radar_heading + radar_rotation
  end
  def history_for_bullet(target_history)
    my_pos = {x: self.x, y: self.y}
    max_distance = [
      to_distance(self, {x: 0, y:0}),
      to_distance(self, {x: battlefield_width, y:0}),
      to_distance(self, {x: battlefield_width, y:battlefield_height}),
      to_distance(self, {x: 0, y:battlefield_height})
    ].sort!.last
    bullet_distance = BULLET_SPEED
    max_generations = (max_distance / BULLET_SPEED).to_i + 1
    (1..max_generations).each do |generation|
      history = target_history.next generation
      break if history.nil?
      return history if to_distance(self, history) <= bullet_distance
      bullet_distance += BULLET_SPEED
    end
    trace("history_for_bullet : not found max=#{max_generations}")
    nil
  end
  def try_fire(target_history)
    unless DEBUG_FIRE
      return false if gun_heat > 0
    end
    history = history_for_bullet(target_history)
    return false if history.nil?

    if DEBUG_FIRE
      target_history.dump_histories
      target_history.dump_nexts
    end

    bullet_distance = to_distance(self, history)
    target_directions = []
    from = {x: self.x, y: self.y}
    target_directions << to_direction(from, {x: history.x - size / 2, y: history.y - size / 2})
    target_directions << to_direction(from, {x: history.x + size / 2, y: history.y - size / 2})
    target_directions << to_direction(from, {x: history.x - size / 2, y: history.y + size / 2})
    target_directions << to_direction(from, {x: history.x + size / 2, y: history.y + size / 2})
    target_directions.sort!()
    if self.gun_heading <= target_directions.first or self.gun_heading >= target_directions.last
      if DEBUG_FIRE
        debug_draw_point history.x, history.y, 1 * size, 0xff00ffff
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
      debug_draw_point_by_degree self, gun_heading, to_distance(self, history), strength * size
    end
    true
  end
end
