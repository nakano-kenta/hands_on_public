require 'rrobots'

class QuickShooter
  include Robot

  def tick events
    turn_radar 45
    if @will_fire
      fire 3
      @will_fire = false
    end

    @scanned_by_name ||= {}
    events['robot_scanned'].each{|scanned|
      @scanned_by_name[scanned[:name]] = {
        latest: time,
        direction: scanned[:direction]
      }
    }
    @scanned_by_name.each do |name, scanned|
      next unless scanned
      @scanned_by_name[name] = nil if (time - scanned[:latest]) > 10
      diff = (scanned[:direction] - gun_heading) % 360
      diff -= 360 if diff > 180
      diff += 360 if diff < -180
      scanned[:diff] = diff
    end

    nearest = @scanned_by_name.values.min do |a, b|
      a[:diff] <=> b[:diff]
    end

    if nearest
      turn nearest[:diff]
      turn_gun (nearest[:diff] - 10) if nearest[:diff] * (nearest[:diff] - 10) > 0
      if nearest[:diff].abs <= 30 and gun_heat == 0
        @will_fire = true
      end
    end
  end
end
