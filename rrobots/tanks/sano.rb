require 'rrobots'
class Sano
  include Robot

  ARRIVAL_TIME_THRESHOLD = 50
  SCAN_SAVE_TIME_THRESHOLD = 200
  TARGET_SAVE_TIME_THRESHOLD = 100
  
  MAX_TURN_DIRECTION = 10
  MAX_TURN_GUN_DIRECTION = 30
  BULLET_SPEED = 30
  
  DIFF_ARRIVAL_DISTANCE_THRESHOLD = 15
  
  ATTACK_ACCEL = {:max => 1.0, :min => -0.5}
  
  def initialize
    @enemy_y = 0
    @enemy_x = 0
    @fire_flg = false
    @turn_diff = 0
    
    @turn_direction = 0
    @turn_gun_direction = 3
    @turn_radar_direction = 60
    @acceleration = 0
    
    # スキャンした結果+付加情報(位置、速度、加速度、向き、向きの変化の速度、現在時間)
    @enemies_history = {}
    
    # 攻撃対象情報(現在からの攻撃時間、着弾位置)
    @targets = []
    
    @target = nil
    
  end
  
  def tick events
    if game_over
      stop
      return 
    end
  
    if @fire_flg
      fire 3
      @fire_flg = false
    end

    # 敵の検知
    scan_enemies
    
    set_targets
    
    set_attack_target
    
    set_tunk_param
    
    turn_radar @turn_radar_direction
    
    if @turn_direction != 0
      turn @turn_direction
    end
    
    if @turn_gun_direction != 0
      turn_gun @turn_gun_direction
    end
    
    if @acceleration != 0
      accelerate @acceleration
    end
    
  end
  
  # 索敵結果を履歴保持する 
  def scan_enemies
    
    # 古い履歴を削除
    @enemies_history.each do |name, enemy|
      enemy.delete_if {|history| time - history[:time] > SCAN_SAVE_TIME_THRESHOLD}
    end
    
    if events['robot_scanned'].empty?
      return
    end
    
#     puts("scanned")
    
    events['robot_scanned'].each do |enemy|
      name = enemy[:name]
#       puts("mine = {#{x},#{y}}")
      # TODO distanceの単位
#       p enemy
      @enemies_history[name] ||= []
      @enemies_history[name].push(enemy)
      if @enemies_history[name].size > 4
        @enemies_history[name].shift
      end
      
      set_scan_detail_data(@enemies_history[name])
      
    end
    
#     @turn_radar_direction *= -1
  end
  
  # 索敵結果の情報に詳細な情報を追加する
  def set_scan_detail_data(enemy_histories)
    # 追加情報
    # ・位置(x,y)
    # ・時間
    # ・速度
    # ・向き
    # ・加速度    
    
    # 位置を設定
    enemy_histories.last[:point] = {:x => calcX(x, enemy_histories.last[:direction], enemy_histories.last[:distance]), :y => calcY(y, enemy_histories.last[:direction], enemy_histories.last[:distance])}
    
    enemy_histories.last[:time] = time
    
    if enemy_histories.size >= 2
      
      # Δ時間取得
      dtime = time - enemy_histories[-2][:time]
      # 速度を取得
      speed_x = calcAxisSpeed(enemy_histories[-2][:point][:x], enemy_histories.last[:point][:x], dtime)
      speed_y = calcAxisSpeed(enemy_histories[-2][:point][:y], enemy_histories.last[:point][:y], dtime)
      speed_v = calcSpeed(speed_x, speed_y)
      enemy_histories.last[:speed] = {:speed => speed_v, :x => speed_x, :y => speed_y}
      
      # 向きを取得
      if speed_v > 0
        enemy_histories.last[:heading] = calcHeading(speed_x, speed_v)
      end
      
      # 加速度を取得
      if enemy_histories[-2][:point] and enemy_histories[-2][:speed]
        accel_x = calcAcceleration(enemy_histories[-2][:point][:x], enemy_histories.last[:point][:x], enemy_histories[-2][:speed][:x], dtime)
        accel_y = calcAcceleration(enemy_histories[-2][:point][:y], enemy_histories.last[:point][:y], enemy_histories[-2][:speed][:y], dtime)
        enemy_histories.last[:accelerate] = {:x => accel_x, :y => accel_y}
      end
      
    end
  end
  
  # x軸位置の算出
  def calcX(base_x, direction, distance)
    # x + cos(ラジアン角度) * 距離
    return base_x + Math::cos(direction.to_rad) * distance
  end
  
  # y軸位置の算出
  def calcY(base_y, direction, distance)
    # フィールドの高さ - y - sin(ラジアン角度) * 距離)
    return  base_y - Math::sin(direction.to_rad) * distance
  end

  # 軸基準の速さの算出
  def calcAxisSpeed(before, after, dtime)
    return (after - before) / dtime
  end
  
  # 速さの算出
  def calcSpeed(speed_x, speed_y)
    # √(x軸の速度^2 + y軸の速度^2)
    return Math::hypot(speed_x, speed_y)
  end
  
  # 向きの算出(x軸基準)
  def calcHeading(speed_x, speed_v)
    # acos(x軸の速度 / 速度) * 180 / PI
    return Math::acos(speed_x / speed_v) * 180 / Math::PI
  end
  
  # 加速度の算出
  def calcAcceleration(before, after, before_speed, dtime)
    # x = v0 * t + a * t^2 / 2 
    # a = (x - v0 * t) * 2 / t^2
    # 加速度 = (距離 - 初速度 * 時間) * 2 / 時間^2
    return ((after - before).abs - before_speed * dtime) * 2 / dtime**2
  end
  
  # 攻撃目標の情報設定
  def set_targets
    # 攻撃目標の情報
    # ・名前
    # ・弾の当たる位置(x,y)
    # ・弾の当たる時間
    # ・現時点でのenergy
  
    # 目標の中で時間の差分が[閾値]を超えた場合削除
#     @targets.delete_if {|target| time - target[:time] > TARGET_SAVE_TIME_THRESHOLD}
    @targets = []
    @enemies_history.each do |name, enemy|
      
      # 元の情報の算出に必要な情報が揃っていない場合、次の目標へ
#       if enemy.empty?
#         puts("enemy empty")
#       end
      
      if enemy.size < 3
#         puts("enemy size < 3")
        next
      end
      
      # フィールド内、任意の2点間の最大の距離を算出(対角線)
      max_distance = Math::hypot(battlefield_height, battlefield_width).to_i
             
      attack_target = nil
#       puts("enemy_point = {#{enemy.last[:point]}　enemy_direction=#{enemy.last[:direction]}, enemy_distance=#{enemy.last[:distance]}")
      for time_bullet_arrival in 0..(max_distance / BULLET_SPEED) do
        # 当たる想定のx座標
        arrival_x = enemy.last[:point][:x] + calcAxisLengthBySpeed(enemy.last[:speed][:x], enemy.last[:accelerate][:x], time_bullet_arrival)
        # 当たる想定のy座標
        arrival_y = enemy.last[:point][:y] + calcAxisLengthBySpeed(enemy.last[:speed][:y], enemy.last[:accelerate][:y], time_bullet_arrival)
       
        # 発砲想定の砲塔の向き
        arrival_angle = calcAngle({:x => x, :y => y}, {:x => arrival_x, :y => arrival_y})
#         puts("enemy_point = {#{enemy.last[:point][:x]},#{enemy.last[:point][:y]}}")
#         puts("arrival_point = {#{arrival_x},#{arrival_y}}")
#         puts("enemy.last[:direction] = #{enemy.last[:direction]}")
#         puts("arrival_angle = #{arrival_angle}")
        # 当たる想定位置との距離
        distance = Math::hypot(arrival_x - x, arrival_y - y)
        
        # [向ける事が可能な向き] & [当たる想定位置との距離 と (弾の到達時間 * 弾の速度) が同じ?]場合に攻撃対象に追加
        diff_arrival_distance = (distance - time_bullet_arrival * BULLET_SPEED).abs
        
#          puts("time_bullet_arrival = #{time_bullet_arrival} ,arrival_point = {#{arrival_x},#{arrival_y}, :speed={#{enemy.last[:speed][:x]},#{enemy.last[:speed][:y]}} , :accelerate={#{enemy.last[:accelerate][:x]},#{enemy.last[:accelerate][:y]}}")

        diff_arrival_angle = correctAngle(arrival_angle - gun_heading)
#         if diff_arrival_angle.abs < 2
#           puts("diff_arrival_angle = #{diff_arrival_angle}")
#         end
        if diff_arrival_distance < DIFF_ARRIVAL_DISTANCE_THRESHOLD
          if diff_arrival_angle.abs <= MAX_TURN_GUN_DIRECTION
            if arrival_x >= 0 && arrival_x <= battlefield_width && arrival_y >= 0 && arrival_y <= battlefield_height
#               puts("gun_heading = #{gun_heading}, correctAngle(gun_heading)= #{correctAngle(gun_heading)}")
              attack_target = {:name => name, :time => enemy.last[:time], :time_bullet_arrival => time_bullet_arrival, :x => arrival_x, :y => arrival_y, :diff_arrival_distance => diff_arrival_distance, :arrival_angle => arrival_angle, :diff_arrival_angle => diff_arrival_angle, :energy => enemy.last[:energy]}
              break
            end
          end
        end
      end
      
      #目標に追加
      unless attack_target.nil?
#         puts("add target #{attack_target}")
        @targets.push(attack_target)
      end
    end
  end
  
  def calcAxisLengthBySpeed(speed, acceleration, time)
    # x = v0 * t + a * t^2 / 2 
    return (speed * time) + acceleration * time**2 / 2
  end
  
  # 向き角度算出(2点指定)
  def calcAngle(point, target)
    angle = (Math::atan2(-target[:y] + point[:y], target[:x] - point[:x])) * 180 / Math::PI 
    return angle % 360
  end
  
  # 角度の補正
  def correctAngle(angle)
     ret = angle % 360
    if ret > 180
      ret -= 360
    elsif ret < -180
      ret += 360
    end
    return ret
  end
  
  def set_attack_target
    @attack_target = pick_target(@targets)
    
    # 次目標がない場合終了
    unless @attack_target
      @fire_flg = false
      return
    end
  end
  
  def pick_target(targets)
#     targets.each do |target|
#       p target
#     end
    if targets.empty?
#        puts("empty targets")
      return nil
    end
#     return targets.min_by {|target| target[:diff_arrival_angle]}
    return targets.last
  end
  
  # 最も近い目標を取得
  def nearest_target(targets, x, y)
    nearest = nil
    unless targets.empty?
      nearest = targets.min_by {|target| Math::hypot(target[:x] - x, target[:y] - y)}
    end
    
    return nearest
  end
  
  def set_tunk_param
    unless @attack_target
#       puts("default move")
      # デフォルトの移動
      
      if time % 10 == 5
        @acceleration = rand(-1.0..1.0)
      else
        @acceleration = 0
      end
      if time % 20 < 10
        @turn_direction = rand(-10..0)
      else
        @turn_direction = rand(1..10)
      end
       @turn_gun_direction = default_gun_angle
      return
    else
    
      @acceleration = rand(-1.0..1.0)
      @acceleration = rand(ATTACK_ACCEL[:min]..ATTACK_ACCEL[:max])
#       puts("fire")
      
      # 攻撃対象が存在する場合、自機、砲塔の向きを調整する
      @turn_direction = MAX_TURN_DIRECTION if @attack_target[:diff_arrival_angle] > 0
      @turn_direction = MAX_TURN_DIRECTION * -1 if @attack_target[:diff_arrival_angle] < 0
      @turn_gun_direction = @attack_target[:diff_arrival_angle] - @turn_direction
      
      if (@attack_target[:diff_arrival_angle] - @turn_direction).abs <= MAX_TURN_GUN_DIRECTION + 2
        @fire_flg = true
      end
    end
  end

  def default_gun_angle
    nearest_agle = 0
    @enemies_history.each do |name, enemy|
      if nearest_agle.abs < (enemy.last[:direction] - gun_heading).abs
        nearest_agle = enemy.last[:direction] - gun_heading
      end
    end
    return nearest_agle
  end
end
