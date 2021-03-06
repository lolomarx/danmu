# -*- encoding : utf-8 -*-
require 'socket'
require 'digest'
require 'securerandom'
require 'logger'
require_relative '../models/message'
require_relative '../misc/logging'

# INFO 代表的是一些琐碎的操作
# DEBUG 


class DanmuClient
  include Logging

  DANMU_SERVER = "danmu.douyutv.com"
  DANMU_PORT = 8602

  def initialize(room,auth_dst_ip,auth_dst_port)
    @room = room
    @room_id = room.room_id
    @auth_dst_ip = auth_dst_ip
    @auth_dst_port = auth_dst_port
    @dev_id = SecureRandom.uuid.to_s.gsub('-','').upcase 
  end

  def start
    do_main
  end

  def do_main
    logger.info("准备登陆认证")
    do_login
    print_room_status
    if @live_stat == "离线"
      logger.info("主播离线中,正在退出...")
      exit
    elsif
      logger.info("主播在线中,准备获取弹幕...")
      loop { get_danmu  }
    end

  end


  def do_login
    @danmu_auth_socket = TCPSocket.new @auth_dst_ip,@auth_dst_port
    @danmu_socket = TCPSocket.new DANMU_SERVER,DANMU_PORT
    logger.info("初始化DAMMU_SOCKET和DANMU_AUTH_SOCKET")
    send_auth_loginreq_msg
    str = @danmu_auth_socket.recv(4000)
     #puts "<>1<><"+str
    if str.include? "live_stat@=0"
      @live_stat = "离线"
    elsif str.include? "live_stat@=1"
      @live_stat = "在线"
      @username= str[/\/username@=(.+)\/nickname/,1]
       #puts "----" + @username
      str = @danmu_auth_socket.recv(4000)
       #puts "<>2<><"+str
      @gid = str[/\/gid@=(\d+)\//,1]
      @weight = str[/\/weight@=(\d+)\//,1]
      @fans_count = str[/\/fans_count@=(\d+)\//,1]
      #puts "<->" + @live_stat.to_s + @weight.to_s + @fans_count.to_s
       #puts @gid + "----"
      send_qrl_msg
      str = @danmu_auth_socket.recv(4000)
       #puts "<>3<><"+str
      str = @danmu_auth_socket.recv(4000)
       #puts "<>4<><"+str
      send_keeplive_msg
      str = @danmu_auth_socket.recv(4000)
       #puts "<>5<><"+str
      data = "type@=loginreq/username@="+@username+"/password@=1234567890123456/roomid@=" + @room_id.to_s + "/"
      all_data = message(data)
      @danmu_socket.write all_data
      #puts all_data
      str = @danmu_socket.recv(4000)
       #puts str
      send_join_group_msg 
      logger.info("发送心跳包")
      do_keeplive
    end

  end

  def message(content)
    Message.new(content).to_s
  end

  def do_keeplive
    Thread.new do
      loop do
        #puts "--> KeepAlive"
        send_keeplive_msg
        sleep 40
        @danmu_socket.write message("type@=keeplive/tick@=" + timestamp + "/")
      end
    end
  end

  def send_keeplive_msg
      data = "type@=keeplive/tick@=" + timestamp + "/vbw@=0/k@=19beba41da8ac2b4c7895a66cab81e23/"
      msg = message(data)
      @danmu_auth_socket.write msg
  end
  def send_auth_loginreq_msg
      time = timestamp 
      vk = Digest::MD5.hexdigest(time + "7oE9nPEG9xXV69phU31FYCLUagKeYtsF" + @dev_id)
      data = "type@=loginreq/username@=/ct@=0/password@=/roomid@="+@room_id.to_s+"/devid@="+@dev_id + "/rt@="+timestamp+"/vk@="+vk+"/ver@=20150929/"
      msg = message(data)
      @danmu_auth_socket.write msg
  end

  def send_loginreq_msg
      data = "type@=loginreq/username@="+@username+"/password@=1234567890123456/roomid@="+@room_id.to_s+"/"
      msg = message(data)
      @danmu_socket.write msg
  end
  def send_join_group_msg
      data  = "type@=joingroup/rid@=" + @room_id.to_s + "/gid@="+@gid+"/"
      msg = message(data)
      @danmu_socket.write msg
  end

  def send_qrl_msg
      data  = "type@=qrl/rid@=" + @room_id.to_s + "/"
      msg = message(data)
      @danmu_auth_socket.write msg
  end

  def get_danmu
    danmu_data = @danmu_socket.recv(4000).force_encoding("UTF-8")
    if not danmu_data.include? "type@="
      logger.info "非消息"
    elsif danmu_data.include? "type@=error"
      logger.info "弹幕认证超时"
    else
      #logger.info(danmu_data)
      #puts danmu_data
      type = danmu_data[danmu_data.index("type@=")..-3]
      str = type.gsub('@S','/').gsub('@A=',':').gsub('@=',':').encode("UTF-16be", :invalid=>:replace, :replace=>"?").encode('UTF-8')
      type = str[/type:(.+?)\//,1]
      #puts type
      if type == "chatmessage"
        type_zh = "弹幕"
        sender_id = str[/\/sender:(.+?)\//,1]
        nickname = str[/\/snick:(.+?)\//,1]
        content =  str[/\/content:(.+?)\//,1]
        strength = str[/\/strength:(.+?)\//,1]
        level = str[/\/level:(\d+?)\//,1]
        time  = Time.now.to_s
        puts "|" + type_zh + "| " + align_left_str(nickname,20," ") + align_left_str("<Lv:#{level}>",8," ") + align_left_str("(#{sender_id})",13," ") + align_left_str("[#{strength}]",10," ") + "@ #{time}: #{content} "
      elsif type == "userenter"
        type_zh = "入房"
        user_id = str[/\/:id:(.+?)\//,1]
        nickname = str[/\/nick:(.+?)\//,1]
        strength = str[/\/strength:(.+?)\//,1]
        time  = Time.now.to_s
        level = str[/\/level:(\d+)\//,1]
        puts "|" + type_zh + "| " + align_left_str(nickname,20," ") + align_left_str("<Lv:#{level}>",8," ") + align_left_str("(#{user_id})",13," ") + align_left_str("[#{strength}]",10," ") + "@ #{time}"
        #puts "|#{type_zh}| #{nickname}  <Lv:#{level}> (#{user_id}) [#{strength}] @ #{time}"
      elsif type == "dgn"
        type_zh = "未知"
        level = str[/\/level:(\d+?)\//,1]
        user_id = str[/\/sid:(.+?)\//,1]
        nickname = str[/\/src_ncnm:(.+?)\//,1]
        hits = str[/\/hits:(.+?)\//,1]
        time  = Time.now.to_s
        puts "|" + type_zh + "| " + align_left_str(nickname,20," ") + align_left_str("<Lv:#{level}>",8," ") + align_left_str("(#{user_id})",13," ") + align_left_str("[#{"Unknown"}]",10," ") + "@ #{time}: #{hits} hits "
        #puts "|#{type_zh}| #{nickname}  <Lv:#{level}> (#{user_id}) @ #{time}"
      end

    end
  end

  def recv
    @danmu_socket.recv(4000)
  end

  def stop
    @danmu_socket.close
    @danmu_auth_socket.close
  end
  
  def timestamp
    Time.now.to_i.to_s
  end

  def print_room_status()
    puts "========================================="
    puts "= Room Infomation                       ="
    puts "========================================="
    puts "= 房间: #{@room.room_name}(#{@room.room_id})"
    puts "= 主播: #{@room.owner_name}"
    puts "= 公告: #{@room.room_gg_show}"
    puts "= 标签: #{@room.room_tags}"
    puts "= 在线: #{@live_stat}"
    puts "= 粉丝: #{@fans_count}"
    puts "= 财产: #{@weight}"
    puts "= DANMU IP DST : #{@auth_dst_ip}:#{@auth_dst_port}\t="
    puts "========================================="
  end

  def align_left_str(raw_str,max_length,filled_chr)
    my_length = 0
    for i in 0...raw_str.size
      if raw_str[i].ord > 127 || raw_str[i].ord <=0
        my_length += 1
      end
      my_length += 1
    end
    if (max_length - my_length) > 0
      raw_str + filled_chr * ( max_length - my_length )
    else
      raw_str
    end
  end

end


