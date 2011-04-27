require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe NotesStructuredTextJsonMessages do
  describe "json_messages" do
    it "should open each file and call json_messages_from_stream with it" do
      output_dir = Object.new
      input_files = [Object.new, Object.new]
      options = {}

      input0 = Object.new
      input1 = Object.new
      mock(File).open(input_files[0], "r"){|f,opts,block| block.call(input0)}
      mock(File).open(input_files[1], "r"){|f,opts,block| block.call(input1)}
      
      mock(NotesStructuredTextJsonMessages).json_messages_from_stream(output_dir, input0, options)
      mock(NotesStructuredTextJsonMessages).json_messages_from_stream(output_dir, input1, options)

      NotesStructuredTextJsonMessages.json_messages(output_dir, input_files, options)
    end
  end

  describe "json_messages_from_stream" do
    it "should call process_block for each block retrieved from the stream" do
      output_dir = Object.new
      input = Object.new
      blocks = [nil, ["foo", "bar"], ["baz", "boo"]]

      mock(NotesStructuredTextJsonMessages).read_block(input).times(3){blocks.pop}

      mock(NotesStructuredTextJsonMessages).process_block(output_dir, ["baz", "boo"], anything)
      mock(NotesStructuredTextJsonMessages).process_block(output_dir, ["foo", "bar"], anything)

      NotesStructuredTextJsonMessages.json_messages_from_stream(output_dir, input)
    end
  end

  describe "with_mappings" do
    it "should write mapping JSON if mapping_file option is given" do
      opts = Object.new
      mf = Object.new
      mfs = StringIO.new
      stub(opts).[](:mapping_file){mf}
      mock(File).open(mf, "w"){|f,m,block| block.call(mfs)}

      NotesStructuredTextJsonMessages.with_mappings(opts) do
        NotesStructuredTextJsonMessages.collect_mapping({:notes_dn=>"CN=foo mcfoo/OU=foofoo/O=foo"}, 
                                                        {:email_address=>"foo.mcfoo@foo.com"})
        NotesStructuredTextJsonMessages.collect_mapping({:notes_dn=>"CN=bar mcbar/OU=barbar/O=bar"}, 
                                                        {:email_address=>"bar.mcbar@bar.com"})
      end

      j = JSON.parse(mfs.string)
      j.should == [[{"notes_dn"=>"CN=foo mcfoo/OU=foofoo/O=foo"}, {"email_address"=>"foo.mcfoo@foo.com"}],
                   [{"notes_dn"=>"CN=bar mcbar/OU=barbar/O=bar"}, {"email_address"=>"bar.mcbar@bar.com"}]]
    end
  end

  describe "readblock" do
    it "should return lines read from a stream until the first empty line" do
      input = <<-EOF
foo
bar

baz
boo
EOF
      io = StringIO.new(input)
      NotesStructuredTextJsonMessages.read_block(io).should == ["foo", "bar"]
      NotesStructuredTextJsonMessages.read_block(io).should == ["baz", "boo"]
    end

    it "should return nil if the input stream is at EOF" do
      io = StringIO.new("foo\nbar")
      NotesStructuredTextJsonMessages.read_block(io).should == ["foo", "bar"]
      NotesStructuredTextJsonMessages.read_block(io).should == nil
    end
  end

  describe "is_distinguished_name?" do
    it "should return true if the address contains a CN=... string" do
      NotesStructuredTextJsonMessages.is_distinguished_name?("CN=foo bar/OU=before/O=after").should == true
    end

    it "should return true if the address is a compact DN" do
      NotesStructuredTextJsonMessages.is_distinguished_name?("foo bar/before/after").should == true
    end

    it "should return false for an internet email address" do
      NotesStructuredTextJsonMessages.is_distinguished_name?("foo@bar.com").should == false
    end
  end

  describe "normalize_distinguished_name" do
    it "should remove a trailing @DOMAIN" do
      NotesStructuredTextJsonMessages.normalize_distinguished_name("CN=foo mcfoo/OU=foofoo/O=foo@foo").should == "CN=foo mcfoo/OU=foofoo/O=foo"
    end

    it "should expand compact distinguished names" do
      NotesStructuredTextJsonMessages.normalize_distinguished_name("foo mcfoo/foofoo/foo").should == "CN=foo mcfoo/OU=foofoo/O=foo"
    end

    it "should raise an exception for a badly formatted compact dn" do
      lambda {
        NotesStructuredTextJsonMessages.normalize_distinguished_name("foo mcfoo/foofoo")
      }.should raise_error(/badly formatted compact dn/)
    end

    it "should do nothing to a regular distinguished names" do
      NotesStructuredTextJsonMessages.normalize_distinguished_name("CN=foo mcfoo/OU=foofoo/O=foo").should == "CN=foo mcfoo/OU=foofoo/O=foo"
    end
  end

  describe "is_message_block?" do
    it "should return true if the block contains a line which start with '$MessageID: ' " do
      NotesStructuredTextJsonMessages.is_message_block?( ["foo", "$MessageID: bar", "baz"] ).should == true
    end

    it "should return false if there are no lines starting with '$MessageID: ' in the block" do
      NotesStructuredTextJsonMessages.is_message_block?( ["foo", "bar", "baz"] ).should == false
    end

    it "should not be case-sensitive" do
      NotesStructuredTextJsonMessages.is_message_block?( ["foo", "$MESSAGEID: bar", "baz"] ).should == true
      NotesStructuredTextJsonMessages.is_message_block?( ["foo", "$messageID: bar", "baz"] ).should == true
      NotesStructuredTextJsonMessages.is_message_block?( ["foo", "$messageid: bar", "baz"] ).should == true
    end
  end

  describe "header_value" do
    it "should extract the first occurence of a header from the block" do
      NotesStructuredTextJsonMessages.header_value(["Foo: foo", "Bar: bar", "Baz: baz"], "Foo").should == "foo"
    end

    it "should strip whitespace" do
      NotesStructuredTextJsonMessages.header_value(["Foo:   foo   ", "Bar: bar", "Baz: baz"], "Foo").should == "foo"
    end
    it "should return nil if there are no occurences of the heaer in the block" do
      NotesStructuredTextJsonMessages.header_value(["Boo: foo", "Bar: bar", "Baz: baz"], "Foo").should == nil
    end

    it "should not be case-sensitive" do
      NotesStructuredTextJsonMessages.header_value(["fOO: foo", "Bar: bar", "Baz: baz"], "Foo").should == "foo"
    end
  end

  describe "header_values" do
    it "should extract an array of values for the header if present" do
      NotesStructuredTextJsonMessages.header_values(["Foo: foo", "Bar: bar", "Baz: baz"], "Foo").should == ["foo"]
      NotesStructuredTextJsonMessages.header_values(["Foo: a,b,c", "Bar: bar", "Baz: baz"], "Foo").should == ["a", "b", "c"]
    end

    it "should return nil if there are no occurences of the header" do
      NotesStructuredTextJsonMessages.header_values(["Boo: a,b,c", "Bar: bar", "Baz: baz"], "Foo").should == nil
    end

    it "should strip whitespace" do
      NotesStructuredTextJsonMessages.header_values(["Foo:   a ,\tb  ,  c  ", "Bar: bar", "Baz: baz"], "Foo").should == ["a", "b", "c"]
    end

    it "should strip on a given character" do
      NotesStructuredTextJsonMessages.header_values(["Foo: a b c", "Bar: c d e", "Baz: f g h"], "Bar", " ").should == ["c", "d", "e"]
    end

    it "should strip with a given method" do
      NotesStructuredTextJsonMessages.header_values(['SendTo: "mcfoo, foo" <foo.mcfoo@foo.com>,"bar \\"barry\\" mcbar" <bar.mcbar@bar.com>'],
                                                    "SendTo",
                                                    :split_rfc822_addresses).should ==
        ['"mcfoo, foo" <foo.mcfoo@foo.com>',
         '"bar \\"barry\\" mcbar" <bar.mcbar@bar.com>']
    end
  end

  describe "split_rfc822_addresses" do
    it "should do nothing to a single address" do
      NotesStructuredTextJsonMessages.split_rfc822_addresses('"foo mcfoo" <foo.mcfoo@foo.com>').should ==
        ['"foo mcfoo" <foo.mcfoo@foo.com>']
    end
    
    it "should split a simple case" do
      NotesStructuredTextJsonMessages.split_rfc822_addresses('"foo mcfoo" <foo.mcfoo@foo.com>,"bar mcbar" <bar.mcbar@bar.com>').should ==
        ['"foo mcfoo" <foo.mcfoo@foo.com>','"bar mcbar" <bar.mcbar@bar.com>']
    end
    
    it "should split if there is a comma inside a quoted string" do
      NotesStructuredTextJsonMessages.split_rfc822_addresses('"mcfoo, foo" <foo.mcfoo@foo.com>,"bar mcbar" <bar.mcbar@bar.com>').should ==
        ['"mcfoo, foo" <foo.mcfoo@foo.com>','"bar mcbar" <bar.mcbar@bar.com>']
    end

    it "should split if there is a quoted double-qoute within a string" do
      NotesStructuredTextJsonMessages.split_rfc822_addresses('"foo \\"foo foo\\" mcfoo" <foo.mcfoo@foo.com>,"bar mcbar" <bar.mcbar@bar.com>').should ==
        ['"foo \\"foo foo\\" mcfoo" <foo.mcfoo@foo.com>','"bar mcbar" <bar.mcbar@bar.com>']
    end
  end

  describe "strip_angles" do
    it "should remove angle-brackets if present" do
      NotesStructuredTextJsonMessages.strip_angles("<foo>").should == "foo"
    end

    it "should do nothing if no angle brackets present" do
      NotesStructuredTextJsonMessages.strip_angles("foo").should == "foo"
    end

    it "should do nothing if a single angle bracket present" do
      NotesStructuredTextJsonMessages.strip_angles("<foo").should == "<foo"
      NotesStructuredTextJsonMessages.strip_angles("foo>").should == "foo>"
    end
  end

  describe "process_block" do
    it "should output_json_message if is_message_block?" do
      output_dir = Object.new
      block = Object.new
      json_message = Object.new

      stub(NotesStructuredTextJsonMessages).is_message_block?(block){true}
      mock(NotesStructuredTextJsonMessages).extract_json_message(block, anything){json_message}
      mock(NotesStructuredTextJsonMessages).output_json_message(output_dir, json_message)

      NotesStructuredTextJsonMessages.process_block(output_dir, block)
    end

    it "should ignore if !is_message_block?" do
      output_dir = Object.new
      block = Object.new

      stub(NotesStructuredTextJsonMessages).is_message_block?(block){false}
      dont_allow(NotesStructuredTextJsonMessages).extract_json_message.with_any_args
      dont_allow(NotesStructuredTextJsonMessages).output_json_message.with_any_args

      NotesStructuredTextJsonMessages.process_block(output_dir, block)
    end

    it "should catch and log exceptions during processing" do
      output_dir = Object.new
      block = ["foo", "bar"]
      logger = Object.new

      stub(NotesStructuredTextJsonMessages).logger{logger}
      stub(NotesStructuredTextJsonMessages).is_message_block?(block){true}
      stub(NotesStructuredTextJsonMessages).extract_json_message(block, anything){raise "boo"}

      mock(logger).error(anything) do |err| 
        err.is_a?(Exception).should == true
        err.message.should =~ /boo/
      end
      mock(logger).error(block.join("\n"))

      lambda {
        NotesStructuredTextJsonMessages.process_block(output_dir, block)
      }.should_not raise_error
    end
  end

  describe "process_address" do
    it "should produce a notes_dn hash if is_distinguished_name?" do
      NotesStructuredTextJsonMessages.process_address("CN=foo bar/OU=here/O=there").should == 
        {:name=>"foo bar", :notes_dn=>"CN=foo bar/OU=here/O=there"}
    end

    it "should be case-preserving for distinguished names" do
      NotesStructuredTextJsonMessages.process_address("CN=Foo Bar/OU=Here/O=There").should == 
        {:name=>"Foo Bar", :notes_dn=>"CN=Foo Bar/OU=Here/O=There"}
    end

    it "should strip @FOO off of the end of distinguished names" do
      NotesStructuredTextJsonMessages.process_address("CN=Foo Bar/OU=Here/O=There@There").should == 
        {:name=>"Foo Bar", :notes_dn=>"CN=Foo Bar/OU=Here/O=There"}
    end

    it "should parse with TMail::Address if !is_distinguished_name?" do
      NotesStructuredTextJsonMessages.process_address('"foo bar" <foo@bar.com>').should ==
        {:name=>"foo bar", :email_address=>"foo@bar.com"}
    end

    it "should downcase internet email addresses" do
      NotesStructuredTextJsonMessages.process_address('"Foo Bar" <Foo@Bar.com>').should ==
        {:name=>"Foo Bar", :email_address=>"foo@bar.com"}
    end

    it "should log a warning if an internet email address does not parse to a TMail::Address" do
      logger = Object.new
      stub(NotesStructuredTextJsonMessages).logger{logger}
      
      mock(logger).warn(/does not parse .* TMail::Address/)

      NotesStructuredTextJsonMessages.process_address('Undisclosed recipients:;').should == nil
    end
  end

  describe "process_address_pair" do
    it "should process_address the notes_address if the inet_address is '.'" do
      NotesStructuredTextJsonMessages.process_address_pair(".", "CN=foo bar/OU=here/O=there", {}).should == 
        {:name=>"foo bar", :notes_dn=>"CN=foo bar/OU=here/O=there"}
    end

    it "should process_address the inet_addr if the inet_address is not '.'" do
      NotesStructuredTextJsonMessages.process_address_pair('"foo bar" <foo@bar.com>', "CN=foo bar/OU=here/O=there", {}).should ==     
        {:name=>"foo bar", :notes_dn=>"CN=foo bar/OU=here/O=there"}
    end
  end

  describe "process_addresses" do
    it "should raise an exception if the notes and inet headers do not match" do
      inet_field = Object.new
      notes_field = Object.new
      block = Object.new
      options = {}

      stub(NotesStructuredTextJsonMessages).header_values(block, inet_field, :split_rfc822_addresses){["foo", "bar"]}
      stub(NotesStructuredTextJsonMessages).header_values(block, notes_field, :split_rfc822_addresses){["foo"]}
      
      lambda {
        NotesStructuredTextJsonMessages.process_addresses(block, inet_field, notes_field, options)
      }.should raise_error(/does not match/)
    end

    it "should call process_address_pair if notes and inet headers are both present" do
      inet_field = Object.new
      notes_field = Object.new
      block = Object.new
      options={}

      stub(NotesStructuredTextJsonMessages).header_values(block, inet_field, :split_rfc822_addresses){["foo.mcfoo@foo.com", "bar.mcbar@bar.com"]}
      stub(NotesStructuredTextJsonMessages).header_values(block, notes_field, :split_rfc822_addresses){["CN=foo mcfoo/OU=main/O=foo", "CN=bar mcbar/OU=main/O=bar"]}

      mock(NotesStructuredTextJsonMessages).process_address_pair("foo.mcfoo@foo.com", "CN=foo mcfoo/OU=main/O=foo", options)
      mock(NotesStructuredTextJsonMessages).process_address_pair("bar.mcbar@bar.com", "CN=bar mcbar/OU=main/O=bar", options)

      NotesStructuredTextJsonMessages.process_addresses(block, inet_field, notes_field, options)
    end

    it "should call process_address if an inet header is present" do
      inet_field = Object.new
      notes_field = Object.new
      block = Object.new
      options={}

      stub(NotesStructuredTextJsonMessages).header_values(block, inet_field, :split_rfc822_addresses){["foo.mcfoo@foo.com", "bar.mcbar@bar.com"]}
      stub(NotesStructuredTextJsonMessages).header_values(block, notes_field, :split_rfc822_addresses){nil}

      mock(NotesStructuredTextJsonMessages).process_address("foo.mcfoo@foo.com")
      mock(NotesStructuredTextJsonMessages).process_address("bar.mcbar@bar.com")

      NotesStructuredTextJsonMessages.process_addresses(block, inet_field, notes_field, options)
    end

    it "should call process_address if a notes header is present" do
      inet_field = Object.new
      notes_field = Object.new
      block = Object.new
      options={}

      stub(NotesStructuredTextJsonMessages).header_values(block, inet_field, :split_rfc822_addresses){nil}
      stub(NotesStructuredTextJsonMessages).header_values(block, notes_field, :split_rfc822_addresses){["CN=foo mcfoo/OU=main/O=foo", "CN=bar mcbar/OU=main/O=bar"]}

      mock(NotesStructuredTextJsonMessages).process_address("CN=foo mcfoo/OU=main/O=foo")
      mock(NotesStructuredTextJsonMessages).process_address("CN=bar mcbar/OU=main/O=bar")

      NotesStructuredTextJsonMessages.process_addresses(block, inet_field, notes_field, options)
    end
    
  end

  describe "output_json_message" do
    it "should write the json encoded message to a file named by the MD5 of the message_id" do
      output_dir = "/a/b/c/d"
      json_message = Object.new
      json_struct = {:message_id=>"foo123@foo.com"}

      stub(json_message).[](:message_id){"foo123@foo.com"}
      stub(json_message).to_json{json_struct.to_json}

      output_stream = Object.new
      mock(output_stream).<<(json_struct.to_json){output_stream}

      mock(File).open("/a/b/c/d/#{MD5.hexdigest("foo123@foo.com")}.json", "w") do |fn,m,block|
        block.call(output_stream)
      end

      NotesStructuredTextJsonMessages.output_json_message(output_dir, json_message)
    end
  end

  describe "parse_date" do
    it "should parse a US morning date correctly" do
      dt = NotesStructuredTextJsonMessages.parse_date("01/25/2011 05:21:37 AM")
      dt.is_a?(DateTime).should == true
      dt.mday.should == 25
      dt.mon.should == 01
      dt.year.should == 2011
      dt.hour.should == 5
      dt.min.should == 21
      dt.sec.should == 37
      dt.zone.should == "+00:00"
    end

    it "should parse a US evening date correctly" do
      dt = NotesStructuredTextJsonMessages.parse_date("12/01/2011 05:21:37 PM")
      dt.is_a?(DateTime).should == true
      dt.mday.should == 1
      dt.mon.should == 12
      dt.year.should == 2011
      dt.hour.should == 17
      dt.min.should == 21
      dt.sec.should == 37
      dt.zone.should == "+00:00"
    end
  end

  describe "extract_json_message" do
    def notes_message(options={})
      h = { 
        "$MessageID" => "<foo123@foo.com>",
        "PostedDate" => "02/25/2011 08:06:10 PM",
        "In_Reply_To" => "<bar456@bar.com>",
        "References" => "<bar456@bar.com> <ear789@ear.com>",
        "From" => "CN=foo mcfoo/OU=fooclub/O=foo",
        "SendTo" => "CN=bar mcbar/OU=barclub/O=bar,CN=baz mcbaz/OU=bazclub/O=baz",
        "CopyTo" => "CN=dar mcdar/OU=darclub/O=dar,CN=ear mcear/OU=earclub/O=ear",
        "BlindCopyTo" => "CN=far mcfar/OU=farclub/O=far,CN=gar mcgar/OU=garclub/O=gar"}.merge(options)
      h.map{|k,v| "#{k}:  #{v}" if v}
    end

    it "should raise an exception if there is no message-id" do
      block = notes_message("$MessageID"=>nil)
      lambda {
        NotesStructuredTextJsonMessages.extract_json_message(block)
      }.should raise_error(/no \$MessageID/)
    end

    it "should raise an exception if there is no From: or InetFrom:" do
      block = notes_message("From"=>nil)
     
      lambda {
        NotesStructuredTextJsonMessages.extract_json_message(block)
      }.should raise_error(/no From/)
    end

    it "should raise an exception if there are no recipients" do
      block = notes_message("SendTo"=>nil, "CopyTo"=>nil, "BlindCopyTo"=>nil)
      
      lambda {
        NotesStructuredTextJsonMessages.extract_json_message(block)
      }.should raise_error(/no recipients/)
    end

    it "should raise an exception if there is no PostedDate" do
      block = notes_message("PostedDate"=>nil)
     
      lambda {
        NotesStructuredTextJsonMessages.extract_json_message(block)
      }.should raise_error(/no PostedDate/)
    end

    it "should remove angle-brackets from message_id, in_reply_to and references" do
      block = notes_message
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:message_id].should == "foo123@foo.com"
    end

    it "should parse a US date correctly" do
      block = notes_message
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      d = j[:sent_at]
      d.is_a?(DateTime).should == true
      d.mday.should == 25
      d.month.should == 2
      d.year.should == 2011
      d.hour.should == 20
      d.min.should == 6
      d.sec.should == 10
    end

    it "should parse the From / InetFrom fields" do
      block = notes_message
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:from].should == {:notes_dn=>"CN=foo mcfoo/OU=fooclub/O=foo", :name=>"foo mcfoo"}

      block = notes_message("From"=>'"foo mcfoo" <foo.mcfoo@foo.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:from].should == {:email_address=>"foo.mcfoo@foo.com", :name=>"foo mcfoo"}
      
      block = notes_message("InetFrom"=>'"foo mcfoo" <foo.mcfoo@foo.com>', "From"=>"CN=foo mcfoo/OU=fooclub/O=foo")
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:from].should == {:notes_dn=>"CN=foo mcfoo/OU=fooclub/O=foo", :name=>"foo mcfoo"}

      block = notes_message("InetFrom"=>'.', "From"=>'"foo mcfoo" <foo.mcfoo@foo.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:from].should == {:email_address=>"foo.mcfoo@foo.com", :name=>"foo mcfoo"}
    end

    it "should parse the SendTo / InetSendTo fields" do
      block = notes_message
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:to].should == [{:notes_dn=>"CN=bar mcbar/OU=barclub/O=bar", :name=>"bar mcbar"},
                        {:notes_dn=>"CN=baz mcbaz/OU=bazclub/O=baz", :name=>"baz mcbaz"}]

      block = notes_message("SendTo"=>'"bar mcbar" <bar.mcbar@bar.com>,"baz mcbaz" <baz.mcbaz@baz.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:to].should == [{:email_address=>"bar.mcbar@bar.com", :name=>"bar mcbar"},
                        {:email_address=>"baz.mcbaz@baz.com", :name=>"baz mcbaz"}]

      block = notes_message("InetSendTo"=>'"bar mcbar" <bar.mcbar@bar.com>,"baz mcbaz" <baz.mcbaz@baz.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:to].should == [{:notes_dn=>"CN=bar mcbar/OU=barclub/O=bar", :name=>"bar mcbar"},
                        {:notes_dn=>"CN=baz mcbaz/OU=bazclub/O=baz", :name=>"baz mcbaz"}]

      block = notes_message("InetSendTo"=>'.,"baz mcbaz" <baz.mcbaz@baz.com>', "SendTo"=>'"bar mcbar" <bar.mcbar@bar.com>,CN=baz mcbaz/OU=bazclub/O=baz')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:to].should == [{:email_address=>"bar.mcbar@bar.com", :name=>"bar mcbar"},
                        {:notes_dn=>"CN=baz mcbaz/OU=bazclub/O=baz", :name=>"baz mcbaz"}]
    end

    it "should parse the CopyTo / InetCopyTo fields" do
      block = notes_message
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:cc].should == [{:notes_dn=>"CN=dar mcdar/OU=darclub/O=dar", :name=>"dar mcdar"},
                        {:notes_dn=>"CN=ear mcear/OU=earclub/O=ear", :name=>"ear mcear"}]

      block = notes_message("CopyTo" => '"dar mcdar" <dar.mcdar@dar.com>,"ear mcear" <ear.mcear@ear.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:cc].should == [{:email_address=>"dar.mcdar@dar.com", :name=>"dar mcdar"},
                        {:email_address=>"ear.mcear@ear.com", :name=>"ear mcear"}]

      block = notes_message("InetCopyTo" => '"dar mcdar" <dar.mcdar@dar.com>,"ear mcear" <ear.mcear@ear.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:cc].should == [{:notes_dn=>"CN=dar mcdar/OU=darclub/O=dar", :name=>"dar mcdar"},
                        {:notes_dn=>"CN=ear mcear/OU=earclub/O=ear", :name=>"ear mcear"}]

      block = notes_message("InetCopyTo" => '.,"ear mcear" <ear.mcear@ear.com>',
                            "CopyTo" => '"dar mcdar" <dar.mcdar@dar.com>,CN=ear mcear/OU=earclub/O=ear')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:cc].should == [{:email_address=>"dar.mcdar@dar.com", :name=>"dar mcdar"},
                        {:notes_dn=>"CN=ear mcear/OU=earclub/O=ear", :name=>"ear mcear"}]
    end

    it "should parse the BlindCopyTo / InetBlindCopyTo fields" do
      block = notes_message
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:bcc].should == [{:notes_dn=>"CN=far mcfar/OU=farclub/O=far", :name=>"far mcfar"},
                         {:notes_dn=>"CN=gar mcgar/OU=garclub/O=gar", :name=>"gar mcgar"}]

      block = notes_message("BlindCopyTo" => '"far mcfar" <far.mcfar@far.com>,"gar mcgar" <gar.mcgar@gar.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:bcc].should == [{:email_address=>"far.mcfar@far.com", :name=>"far mcfar"},
                         {:email_address=>"gar.mcgar@gar.com", :name=>"gar mcgar"}]

      block = notes_message("InetBlindCopyTo" => '"far mcfar" <far.mcfar@far.com>,"gar mcgar" <gar.mcgar@gar.com>')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:bcc].should == [{:notes_dn=>"CN=far mcfar/OU=farclub/O=far", :name=>"far mcfar"},
                         {:notes_dn=>"CN=gar mcgar/OU=garclub/O=gar", :name=>"gar mcgar"}]

      block = notes_message("InetBlindCopyTo" => '.,"gar mcgar" <gar.mcgar@gar.com>',
                            "BlindCopyTo" => '"far mcfar" <far.mcfar@far.com>,CN=gar mcgar/OU=garclub/O=gar')
      j = NotesStructuredTextJsonMessages.extract_json_message(block)
      j[:bcc].should == [{:email_address=>"far.mcfar@far.com", :name=>"far mcfar"},
                         {:notes_dn=>"CN=gar mcgar/OU=garclub/O=gar", :name=>"gar mcgar"}]
    end
  end
end
