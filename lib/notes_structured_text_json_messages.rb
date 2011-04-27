require 'md5'
require 'tmail'

module NotesStructuredTextJsonMessages
  class << self
    attr_accessor :logger
    attr_accessor :stats
    attr_accessor :mappings
  end

  module_function

  def log
    yield logger if logger
  end

  def increment_stats(key)
    self.stats[key] = (self.stats[key]||0) + 1
  end
  
  def collect_mapping(addr1, addr2)
    self.mappings << [addr1, addr2] if self.mappings
  end

  def with_mappings(options)
    mapping_file = options[:mapping_file]
    log{|logger| logger.info "using mapping_file: #{options[:mapping_file]}"} if mapping_file
    self.mappings=[]
    yield
  ensure
    if mapping_file
      File.open(mapping_file, "w") do |output|
        output << "[\n"
        output << self.mappings.map(&:to_json).join(",\n")
        output << "\n]"
      end
    end
  end

  def with_stats
    self.stats={}
    yield
  ensure
    self.stats.each do |k,v|
      log{|logger| logger.info("#{k}: #{v}")}
    end
  end

  def json_messages(output_dir, input_files, options={})
    with_stats do
      with_mappings(options) do
        [*input_files].each do |input_file|
          File.open(input_file, "r") do |input|
            json_messages_from_stream(output_dir, input, options)
          end
        end
      end
    end
  end

  def json_messages_from_stream(output_dir, input, options={})
    block = nil
    process_block(output_dir, block, options) while block=read_block(input)
  end

  def read_block(input)
    return nil if input.eof?
    block = []
    begin
      l = input.readline.chomp
      block << l if l.length>0
    end while !input.eof? && l != ""
    block
  end

  def is_message_block?(block)
    !!header_value(block, MESSAGE_ID)
  end

  def is_distinguished_name?(addr)
    !!(addr =~ /CN=/)
  end

  def header_value(block, header)
    patt = /^#{Regexp.quote(header)}: /i
    h = block.find{|l| l =~ patt}
    h.gsub(patt, '').strip if h
  end

  def header_values(block, header, split_on=",")
    h = header_value(block, header)
    if h
      if split_on.is_a?(Symbol)
        self.send(split_on, h)
      else
        h.split(split_on)
      end.map(&:strip)
    end
  end

  def split_rfc822_addresses(header)
    addresses = []
    quoted_pair = false
    quoted_string = false
    buf = ""
    header.each_char do |c|
      if quoted_pair
        buf << c
        quoted_pair = false
      elsif quoted_string && c=='\\'
        buf << c
        quoted_pair = true
      elsif !quoted_string && c==','
        addresses << buf
        buf = ""
      elsif !quoted_string && c=='"'
        buf << c
        quoted_string = true
      elsif quoted_string && c=='"'
        buf << c
        quoted_string = false
      else
        buf << c
      end
    end
    addresses << buf if buf.length>0
    addresses
  end
  
  def strip_angles(value)
    value.gsub(/<([^>]*)>/, '\1')
  end

  def process_block(output_dir, block, options={})
    if is_message_block?(block)
      json_message = extract_json_message(block, options)
      output_json_message(output_dir, json_message)
      increment_stats(:message)
    else
      increment_stats(:non_message)
    end
  rescue Exception=>e
    increment_stats(:failed_message)
    log do |logger| 
      logger.error(e)
      logger.error(block.join("\n"))
    end
  end

  MESSAGE_ID = "$MessageID"
  POSTED_DATE = "PostedDate"
  IN_REPLY_TO = "in_reply_to"
  REFERENCES = "references"
  FROM = "From"
  TO = "SendTo"
  CC = "CopyTo"
  BCC = "BlindCopyTo"
  INET_FROM = "InetFrom"
  INET_TO = "InetSendTo"
  INET_CC = "InetCopyTo"
  INET_BCC = "InetBlindCopyTo"
  
  def process_address(addr)
    if is_distinguished_name?(addr)
      name = addr[/CN=([^\/]*)/, 1]
      h = {:notes_dn=>addr}
      h[:name] = name if name
      h
    else
      ta = TMail::Address.parse(addr)
      if ta.is_a?(TMail::Address)
        h = {:email_address=>ta.address.downcase}
        h[:name] = ta.name if ta.name
        h
      else
        log{|logger| logger.warn("addr does not parse to a TMail::Address: #{addr}")}
      end
    end
  end

  def process_address_pair(inet_addr, notes_addr, options)
    if inet_addr == "."
      process_address(notes_addr)
    else
      inet_addr = process_address(inet_addr)
      notes_addr = process_address(notes_addr)

      collect_mapping(notes_addr, inet_addr)

      inet_addr
    end
  end

  def process_addresses(block, inet_field, notes_field, options)
    inet_h = header_values(block, inet_field, :split_rfc822_addresses)
    notes_h = header_values(block, notes_field, :split_rfc822_addresses)

    if inet_h && notes_h
      if inet_h.length == notes_h.length
        inet_h.zip(notes_h).map do |inet_addr, notes_addr|
          process_address_pair(inet_addr, notes_addr, options)
        end
      else
        raise "#{inet_field}: does not match #{notes_field}:"
      end
    elsif inet_h
      inet_h.map{|addr| process_address(addr)}
    elsif notes_h
      notes_h.map{|addr| process_address(addr)}
    else
      nil
    end
  end

  NOTES_US_DATE_FORMAT = "%m/%d/%Y %I:%M:%S %p"

  def parse_date(date, options={})
    DateTime.strptime(date, NOTES_US_DATE_FORMAT)
  end

  def extract_json_message(block, options={})
    message_id_h = header_value(block, MESSAGE_ID) 
    if !message_id_h
      increment_stats(:failure_no_message_id)
      raise "no #{MESSAGE_ID}"
    end
    message_id = strip_angles(message_id_h)

    posted_date_h = header_value(block, POSTED_DATE)
    if !posted_date_h
      increment_stats(:failure_no_posted_date)
      raise "no #{POSTED_DATE}"
    end
    posted_date = parse_date(posted_date_h, options)

    in_reply_to_h = header_value(block, IN_REPLY_TO)
    in_reply_to = strip_angles(in_reply_to_h) if in_reply_to_h

    references_h = header_values(block, REFERENCES, " ")
    references = references_h.map{|r| strip_angles(r)} if references_h

    froms = process_addresses(block, INET_FROM, FROM, options)
    if !froms || froms.size>1
      increment_stats(:failure_from)
      raise "no From:, or more than one From:"
    end
    from = froms[0]
    to = process_addresses(block, INET_TO, TO, options)
    cc = process_addresses(block, INET_CC, CC, options)
    bcc = process_addresses(block, INET_BCC, BCC, options)

    if (to||[]).size + (cc||[]).size + (bcc||[]).size == 0
      increment_stats(:failure_no_recipients)
      raise "no recipients" 
    end
    
    { :message_type=>"email",
      :message_id=>message_id,
      :sent_at=>posted_date,
      :in_reply_to=>in_reply_to,
      :references=>references,
      :from=>from,
      :to=>to,
      :cc=>cc,
      :bcc=>bcc}
  end

  def output_json_message(output_dir, json_message)
    fname = File.join(output_dir, "#{MD5.hexdigest(json_message[:message_id])}.json")
    File.open(fname, "w"){|out| out << json_message.to_json}
  end

end
