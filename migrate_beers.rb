#!/usr/bin/env ruby

# TODO:
#   * [DONE] Strip (partial) brewery names from beer names (e.g. great lakes big black smoke [great lakes brewing] -> big black smoke [great lakes brewing])
#   * Penalty for non-matching words
#   * Look for common 2-grams (splitting on word-boundaries)
#

require 'csv'
require 'pry'

class String
  def words
    split(/[\s-]+/)
  end

  def normalize(rules)
    normalized = self.dup
    rules.each do |rule, replacement|
      normalized.gsub!(rule, replacement)
    end
    normalized = normalized.tr(
      "ÀÁÂÃÄÅàáâãäåĀāĂăĄąÇçĆćĈĉĊċČčÐðĎďĐđÈÉÊËèéêëĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħÌÍÎÏìíîïĨĩĪīĬĭĮįİıĴĵĶķĸĹĺĻļĽľĿŀŁłÑñŃńŅņŇňŉŊŋÒÓÔÕÖØòóôõöøŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšſŢţŤťŦŧÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲųŴŵÝýÿŶŷŸŹźŻżŽž",
      "AAAAAAaaaaaaAaAaAaCcCcCcCcCcDdDdDdEEEEeeeeEeEeEeEeEeGgGgGgGgHhHhIIIIiiiiIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnNnnNnOOOOOOooooooOoOoOoRrRrRrSsSsSsSssTtTtTtUUUUuuuuUuUuUuUuUuUuWwYyyYyYZzZzZz"
    )
    normalized.downcase!
    normalized
  end

  def strip_common_prefix_words!(other)
    words_self = self.words
    words_other = other.words
    until words_self.empty? || words_other.empty? || words_self.first != words_other.first
      words_self.shift
      words_other.shift
    end
    self.replace(words_self.join(" "))
  end

  def ngrams(size)
    self.words.each_cons(size).to_a
  end
end

def extract_frequencies(arrays)
  freq = Hash.new(0)
  arrays.each do |x|
    x.each { |w| freq[w] += 1 }
  end
  freq
end

def extract_word_frequencies(strings)
  extract_frequencies(strings.map(&:words))
end

def extract_ngram_frequencies(strings, size=2)
  ngrams = strings.map { |s| s.ngrams(size) }
  extract_frequencies(ngrams)
end

class BeerComparator
  def initialize(old_beers, new_beers)
    old_beer_names = old_beers.map { |b| b[:name] }
    new_beer_names = new_beers.map { |b| b[:name] }
    @old_brewery_names = old_beers.map { |b| b[:brewery] }.uniq
    @new_brewery_names = new_beers.map { |b| b[:brewery] }.uniq
    @frequencies = {
      :name => {
        :old => extract_word_frequencies(old_beer_names),
        :new => extract_word_frequencies(new_beer_names),
        :old_ngram => extract_ngram_frequencies(old_beer_names),
        :new_ngram => extract_ngram_frequencies(new_beer_names)
      },
      :brewery => {
        :old => extract_word_frequencies(@old_brewery_names),
        :new => extract_word_frequencies(@new_brewery_names),
        :old_ngram => extract_ngram_frequencies(@old_brewery_names),
        :new_ngram => extract_ngram_frequencies(@new_brewery_names)
      }
    }
    @beers_by_brewery = {
      :old => old_beers.group_by { |b| b[:brewery] },
      :new => new_beers.group_by { |b| b[:brewery] }
    }
  end

  IGNORED_WORDS = ['', '-', '/', '+', 'and', 'the', 'of']

  def similarity(old_name, new_name, type)
    if old_name == new_name
      Float::INFINITY
    else
      similarity_words(old_name, new_name, type) + similarity_ngrams(old_name, new_name, type)
    end
  end

  def similarity_words(old_name, new_name, type)
    words_old = old_name.words - IGNORED_WORDS
    words_new = new_name.words - IGNORED_WORDS
    all_words = (words_old | words_new)
    common_words = (words_old & words_new)
    uncommon_words = (all_words - common_words)

    positive_score = 0
    common_words.each do |w|
      return Float::INFINITY if @frequencies[type][:old][w] == 1 && @frequencies[type][:new][w] == 1
      average_frequency = (@frequencies[type][:old][w] + @frequencies[type][:new][w]) / 2.0
      positive_score += 1.0 / (average_frequency || 1.0)
    end
    positive_score /= all_words.size

    negative_score = 0
    uncommon_words.each do |w|
      average_frequency = (@frequencies[type][:old][w] + @frequencies[type][:new][w]) / 2.0
      negative_score += 2.0 / (average_frequency || 1.0)
    end
    negative_score /= all_words.size

    positive_score - negative_score
  end

  def similarity_ngrams(old_name, new_name, type)
    ngrams_old = old_name.ngrams(2)
    ngrams_new = new_name.ngrams(2)
    common_ngrams = (ngrams_old & ngrams_new)
    score = 0
    common_ngrams.each do |ngram|
      return Float::INFINITY if @frequencies[type][:old_ngram][ngram] == 1 && @frequencies[type][:new_ngram][ngram] == 1
      average_frequency = (@frequencies[type][:old_ngram][ngram] + @frequencies[type][:new_ngram][ngram]) / 2.0
      score += 5.0 / (average_frequency || 1.0)
    end
    score
  end

  def match_brewery_name(old_name)
    best_match = @new_brewery_names.max_by do |new_name|
      similarity(old_name, new_name, :brewery)
    end
    [best_match, similarity(old_name, best_match, :brewery)]
  end

  def match(old_beer)
    new_brewery, brewery_score = match_brewery_name(old_beer[:brewery])
    return nil if brewery_score <= 0

    new_brewery_beers = @beers_by_brewery[:new][new_brewery]
    best_match = new_brewery_beers.max_by do |new_beer|
      similarity(old_beer[:name], new_beer[:name], :name)
    end
    score = similarity(old_beer[:name], best_match[:name], :name)

    return nil if score <= 0
    [best_match, score]
  end
end

BREWERY_NORMALIZATION_RULES = {
  /'s(\b|$)/             => 's\1',
  /,/                    => '',
  /&/                    => ' and ',
  /\sCo\.?(\s|$)/          => '\1',
  /\sCompany\.?(\s|$)/     => '\1',
  /\sL\.?L\.?C\.?(\s|$)/   => '\1',
  /\sInc\.?(\s|$)/         => '\1',
  /\sltd\.?(\s|$)/i        => '\1',
  /\slimited(\s|$)/i       => '\1',
  /\sA\.?G\.?(\s|$)/i      => '\1',
  /\sS\.?A\.?(\s|$)/i      => '\1',
  /\sN\.?V\.?(\s|$)/i      => '\1',
  /\sB\.? ?V\.?(\s|$)/i    => '\1',
  /\sC\.?L\.?(\s|$)/i      => '\1',
  /\sA\.?\s?S\.?(\s|$)/i   => '\1',
  /\sGmbH(\s|$)/           => '\1',
  /\s\(samuel adams\)$/i   => '',
  /\s\/ bridgeport brewpub \+ bakery$/ => '',
  /brewing(\s|$)/i       => '\1',
  /(\s|^)brewery(\s|$)/i       => '\1'
}

BEER_NORMALIZATION_RULES = {}

def load_csv(path, headers)
  CSV.read(path).map { |row| Hash[headers.zip(row)] }
end

old_beers = load_csv("old_beers.csv", [:id, :name, :brewery_id, :brewery])
new_beers = load_csv("new_beers.csv", [:id, :name, :brewery_id, :brewery])
perfect_matches = []

old_beers.each do |b|
  b[:brewery] = b[:brewery].normalize(BREWERY_NORMALIZATION_RULES)
  b[:name] = b[:name].normalize(BEER_NORMALIZATION_RULES)
  b[:name].strip_common_prefix_words!(b[:brewery])
end
new_beers.each do |b|
  b[:brewery] = b[:brewery].normalize(BREWERY_NORMALIZATION_RULES)
  b[:name] = b[:name].normalize(BEER_NORMALIZATION_RULES)
  b[:name].strip_common_prefix_words!(b[:brewery])
end

comparator = BeerComparator.new(old_beers, new_beers)

if ARGV[0]
  old_beers = old_beers.select { |b| b[:name] =~ /#{ARGV[0]}/ || b[:brewery] =~ /#{ARGV[0]}/ }
end

old_beers.each do |old_beer|
  best_match, score = comparator.match(old_beer)
  if best_match.nil?
    puts "[ no match ] #{old_beer[:name]} [#{old_beer[:brewery]}]"
  else
    puts "[ #{score} ] #{old_beer[:name]} [#{old_beer[:brewery]}] -> #{best_match[:name]} [#{best_match[:brewery]}]"
  end
end
