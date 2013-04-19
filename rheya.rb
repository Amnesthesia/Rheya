require "cinch"
require "rubygems"
require "mechanize"
require "twitter"
require "sqlite3"

    
class RheyaSpeak
  include Cinch::Plugin
  
  attr_accessor :debug, :db

  debug = true
  
  match /.+/, { method: :process_message }
  match /!speak\s+.+/, { method: :construct_sentence }
  match "I love you", { method: :random_sentence }
  
  # Speak every 1h 15min
  timer 4400, method: :random_sentence
  
  
  
  def initialize(*args)
    super
    @db = SQLite3::Database.new("dictionary.db")
    @db.results_as_hash = true
    @debug = true
    
    # If our tables dont exist, lets set them up :)
    create_structure
    
  end
  
  def create_structure
    @db.execute("create table if not exists words (id INTEGER PRIMARY KEY, word varchar(50) UNIQUE NOT NULL);")
    @db.execute("create table if not exists pairs (word_id integer(8), pair_id integer(8), occurance integer(10));")
    
    if @debug == true
      puts "Should have created tables by now"
    end
    
  end

  def get_id(word)
    
    puts "Attempting to get ID from #{word}"
    # Get the ID for a word
    id = @db.get_first_value("select id from words where word = ?", word)
    
    # If debug is enabled, output some debug information
    if @debug == true
      puts "ID for " % word % " is " % id
    end
    
    # If ID doesnt exist, add the word instead, then return the ID
    if id == nil
      id = add_word(word)
    end
    
    return id
  end

  def get_word(word)
    id = get_id(word)
    
    rows = @db.execute("SELECT * FROM pairs WHERE pair_id = ?", id)
    
    puts rows
    if rows == nil or rows.count == 0
      return "."
    else
      max = rows.count
    end
    
    random_row = Random.rand(max)
    
    next_word = @db.get_first_value("SELECT word FROM words WHERE id = ?", rows[random_row]["word_id"])
    
    if @debug == true
      puts "I randomized a word based on #{word} and got #{next_word} from row #{random_row} out of maximum #{max} rows"
    end
    
    return next_word
  end
  
  def add_word(word)
    @db.execute("INSERT OR IGNORE INTO words VALUES (NULL, ?)", word)
    id = @db.get_first_value("select id from words where word = ?",word)
    
    if @debug == true
      puts "I added #{word} to our dictionary with id #{id}"
    end
    
    return id 
  end
  
  def pair_words(word, word2)
    
    # Get word IDs for two words, then check if they exist in our table
    word1_id = get_id(word)
    word2_id = get_id(word2)
    
    row = @db.get_first_value("SELECT count(*) as c FROM pairs WHERE word_id = ? AND pair_id = ?", word1_id, word2_id)
    
    # If nothing is in there, add it
    if row == nil or row <= 0
      @db.execute("INSERT INTO pairs VALUES (?,?,1)", word1_id, word2_id)
      
      if @debug == true
        puts "I've just paired #{word} (#{word1_id}) to #{word2} (#{word2_id}) :D"
      end
    
    # If something is there, update occurance by 1  
    else
      @db.execute("UPDATE pairs SET occurance = occurance+1 WHERE word_id = ? AND pair_id = ?", word1_id, word2_id)
      
      if @debug == true
        occurance = @db.get_first_value("SELECT occurance FROM pairs WHERE word_id = ? AND pair_id = ?", word1_id, word2_id)
        puts "I updated the occurance of #{word} (#{word1_id}) to #{word2} (#{word2_id}), which is now: #{occurance}"
      end
    end
  end
  
  
  def process_message(message)

    # Make it a string first
    msg = message.message.to_s
    
    if msg =~ /!speak\s.+/
      msg.slice! "!speak "
    end
    
    if msg =~ /!quote\s.+/
      msg.slice! "!quote "
    end
    
    if msg =~ /!tweet\s.+/
      msg.slice! "!tweet "
    end
    
    # Split the sentence into words by splitting on non-word delimiters
    words = msg.split(/\s+/)
    
    # Talk back!
    #message.reply "Neat! " % words.count % " new words to learn! Woop woop!"
    
    # Loop through all words, with the index, to access elements properly
    words.each_with_index do |word,i|
      
      word.downcase!
      # We cant pair the first word, because it doesn't follow any word,
      # so instead we pair each word after the first to the previous word
      if i > 0
        pair_words(word,words[i-1])
      end
    end
  end
  
  def construct_sentence(message)
    
    msg = message.message
    
    if msg =~ /!speak\s.+/
      msg.slice! "!speak "
    end
    
    if msg.match(/^\w+\s+\w+.+/)
      word = msg.split(/\s+/)
      sentence = word.last  
      prev_word = word.last
    else
      word = msg
      sentence = msg
      prev_word = msg
    end
    
    
    i = 0
    
    # Loop with a 1 in 10 chance of ending to construct a randomly sized sentence
    begin  
      prev_word = get_word(prev_word)
      # Append a randomly chosen word based on the previous word in the sentence
      sentence << " " << prev_word
      puts " added %s" %prev_word
      i += 1
      
    end while Random.rand(25) != 8 and prev_word != "."
    sentence.capitalize!
    message.reply sentence
  end
  
  
  def random_sentence(message)
    prev_word = @db.get_first_value("SELECT word FROM words ORDER BY RANDOM() LIMIT 1;")
    sentence = prev_word
    
    
    i = 0
    
    # Loop with a 1 in 10 chance of ending to construct a randomly sized sentence
    begin  
      prev_word = get_word(prev_word)
      # Append a randomly chosen word based on the previous word in the sentence
      sentence << " " << prev_word
      
      i += 1
      
    end while Random.rand(25) != 8 and prev_word != "."
    
    sentence.capitalize!
    message.reply sentence
  end
  
  
end

class ReplyTitle
  include Cinch::Plugin
  
  match /https?:\/\/[\S]+/, { method: :GetTitle}  

  
  def GetTitle(m)
    urls = URI.extract(m.message)
   
    urls.each do |url|
      answer = Format(:grey, "Title: %s" % [Format(:bold, $WWW::Mechanize.new.get(url).title)] )
      m.reply answer
    end
  end
end

class Quotes
  include Cinch::Plugin
  
  attr_accessor :debug, :db, :twit, :last_mention

  debug = true

  match /!quote\s.+/, { method: :add_quote }
  match "!quote", {method: :random_quote }
  match /!tweet\s.+/, { method: :tweet }
  match /!reply\s.+/, { method: :reply }
  match /!follow\s.+/, { method: :follow }
  match /!last/, { method: :last_mentioned }
  match /!read\s.+/, {method: :read }
  timer 600, method: :last_mentioned
  
  
  
  def initialize(*args)
    super
    @db = SQLite3::Database.new("quotes.db")
    @db.results_as_hash = true
    @debug = true
    @twit = Twitter::Client.new(
      :consumer_key => "9x9TByi4BjzXs9N1Oyv3gA",
      :consumer_secret => "3NfBK7yhwHZLz4ZOAyLZ6aN6amaB55nNCNph48PGs",
      :oauth_token => "1363095884-N9tj5FR3iFb2Sokhxi59WLxwRoF1AOWPVZ4uydr",
      :oauth_token_secret => "360KsViDUl7P7ajTmxBYqzNxkW2BnWKAl30Y2Umy4"
    )
    @last_mention = nil
    
    # If our tables dont exist, lets set them up :)
    create_structure

    
  end
  
  def create_structure
    @db.execute("create table if not exists quotes (id INTEGER PRIMARY KEY, quote TEXT);")
    
    if @debug == true
      puts "Should have created tables by now"
    end
  end
  
  def add_quote(message)
    msg = message.message
    
    if msg =~ /!quote\s.+/
      msg.slice! "!quote"
    end
    @db.execute("INSERT INTO quotes VALUES(NULL,?)",msg)
    
    @twit.update(msg)
    
    puts "I added #{msg}"
    
    message.reply "Added :)"
  end
  
  def random_quote(message)
    quote = @db.get_first_value("SELECT quote FROM quotes ORDER BY RANDOM() LIMIT 1;")
    answer = Format(:grey, "As a wise man once said: \"%s\"" % [Format(:bold, quote) ] )
    
    message.reply answer
  end
  
  def tweet(message)
    msg = message.message
    
    if msg =~ /!quote\s.+/
      msg.slice! "!tweet "
    end
    
    @twit.update(msg)  
  end
  
  def last_mentioned(message)
    
    if @last_mentioned != nil
      tweets = @twit.mentions_timeline({ since_id: @last_mentioned.id })
    else
      tweets = @twit.mentions_timeline
    end
    
    if tweets.empty? or tweets.count < 1
      message.reply "Nobody's talking to me .. Everybody hates me :("
    end
    
    tweets.map do |t|
      from = t.from_user.capitalize
      answer = from + " said: " + t.text
      puts answer
      message.reply answer
    end
    
    @last_mentioned = tweets.first
    
  end
  
  def follow(message)
    msg = message.message
    
    if msg =~ /!follow\s.+/
      msg.slice! "!follow "
    end  
    
    if msg =~ /@/
      msg.slice! "@"
    end
    
    if msg =~ /\s/
      msg = msg.split(/\s+/)
      msg.each do |m|
        puts "Attempting to follow %s" % m
        @twit.follow(m)
        message.reply "Followed %s" % m
      end
    else
      puts "Attempting to follow %s" % msg
      @twit.follow(msg)
      message.reply "Followed %s" % msg
    end
    
    
  end
  
  
  def reply(message)
    msg = message.message
    
    if msg =~ /!reply\s.+/
      msg.slice! "!reply "
    end
    
    mess = "@" + @last_mentioned.from_user + " " + msg 
    @twit.update(mess)
  end
  
  def read(message)
    msg = message.message
    
    if msg =~ /!read\s.+/
      msg.slice! "!read "
    end 
    
    tweet = @twit.user_timeline(msg)
    
    message.reply tweet.first.text
  end
  
end


bot = Cinch::Bot.new do
  configure do |conf|
  
    # Set up personality
    conf.nick = "Rheya"
    conf.user = "Rheya"
    conf.realname = "Rheya"
    
    # Set up server
    conf.server = "irc.codetalk.io"
    conf.channels = ["#lobby"]
    conf.port = 6697
    conf.ssl.use = true
    
    # Load some plugins
    
    conf.plugins.plugins = [ReplyTitle, RheyaSpeak, Quotes]
    conf.plugins.prefix = nil
    
  end
  
end


bot.start
