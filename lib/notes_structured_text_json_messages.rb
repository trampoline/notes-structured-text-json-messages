require 'md5'
require 'tmail'

module NotesStructuredTextJsonMessages
  class << self
    attr_accessor :logger
  end

  module_function

  def log
    yield logger if logger
  end
  
  def json_messages(output_dir, input_files, options={})
    [*input_files].each do |input_file|
      File.open(input_file, "r") do |input|
        json_messages_from_stream(output_dir, input, options)
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
    h.split(split_on).map(&:strip) if h
  end
  
  def strip_angles(value)
    value.gsub(/<([^>]*)>/, '\1')
  end

  def process_block(output_dir, block, options={})
    if is_message_block?(block)
      json_message = extract_json_message(block, options)
      output_json_message(output_dir, json_message)
    end
  rescue Exception=>e
    log do |logger| 
      logger.warn(e)
      logger.warn(block.join("\n"))
    end
  end

  MESSAGE_ID = "$MessageID"
  DATE = "PostedDate"
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
      { :name=>name,
        :notes_dn=>addr}
    else
      ta = TMail::Address.parse(addr)
      { :name=>ta.name,
        :email_address=>ta.address}
    end
  end

  def process_address_pair(inet_addr, notes_addr)
    if inet_addr == "."
      process_address(notes_addr)
    else
      process_address(inet_addr)
    end
  end

  def process_addresses(block, inet_field, notes_field)
    inet_h = header_values(block, inet_field)
    notes_h = header_values(block, notes_field)

    if inet_h && notes_h
      if inet_h.length == notes_h.length
        inet_h.zip(notes_h).map do |inet_addr, notes_addr|
          process_address_pair(inet_addr, notes_addr)
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
    message_id = header_value(block, MESSAGE_ID) 
    raise "no #{MESSAGE_ID}" if !message_id
    date_h = header_value(block, DATE)
    raise "no #{DATE}" if !date
    date = parse_date(date_h, options)
    in_reply_to = header_value(block, IN_REPLY_TO)
    references = header_values(block, REFERENCES, " ")
    froms = process_addresses(block, INET_FROM, FROM)
    raise "no From:, or more than one From:" if !froms || froms.size>1
    from = froms[0]
    to = process_addresses(block, INET_TO, TO)
    cc = process_addresses(block, INET_CC, CC)
    bcc = process_addresses(block, INET_BCC, BCC)
    
    { :message_id=>message_id,
      :date=>date,
      :in_reply_to=>in_reply_to,
      :references=>references,
      :from=>from,
      :to=>to,
      :cc=>cc,
      :bcc=>bcc}
  end

  def output_json_message(output_dir, json_message)
    fname = File.join(output_dir, MD5.hexdigest(json_message[:message_id]))
    File.open(fname, "w"){|out| out << json_message.to_json}
  end
end
