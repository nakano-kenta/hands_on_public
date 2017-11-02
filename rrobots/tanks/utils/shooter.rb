module ShooterUtil
  def quick_shoot
    turn_radar 45
    if @will_fire
      fire 3
      @will_fire = false
    end
    events['robot_scanned'].each{|scanned|
      diff = (scanned[:direction] - gun_heading) % 360
      diff -= 360 if diff > 180
      diff += 360 if diff < -180
      if diff.abs <= 30 and gun_heat == 0
        @will_fire = true
        turn_gun diff
        break
      end
    }
    turn_gun 30 unless @will_fire
  end

  def scan_for_fire
    @turn_radar_angle ||= 45
    @scanned_by_name ||= {}
    events['robot_scanned'].each{|scanned|
      @scanned_by_name[scanned[:name]] ||= {}
      @scanned_by_name[scanned[:name]][:latest] = time
      @scanned_by_name[scanned[:name]][:direction] = scanned[:direction]
      @scanned_by_name[scanned[:name]][:distance] = scanned[:distance]
    }
    @scanned_by_name.each do |name, scanned|
      next unless scanned
      @scanned_by_name[name] = nil if (time - scanned[:latest]) > 10
      diff = (scanned[:direction] - gun_heading) % 360
      diff -= 360 if diff > 180
      diff += 360 if diff < -180
      scanned[:diff] = diff
    end

    nearest = @scanned_by_name.values.compact.min do |a, b|
      a[:diff] <=> b[:diff]
    end

    if nearest and nearest[:latest] == time
      @turn_radar_angle *= -1
    end
    turn_radar @turn_radar_angle

    nearest
  end
end
