include Amatch

$redis = Recommendable.redis

def fetch_old_rated_beers
  old_beers = []
  OldBeer.find_each do |beer|
    liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(Beer, beer.id)
    disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(Beer, beer.id)
    old_beers << beer if $redis.scard(liked_by_set) > 0 || $redis.scard(disliked_by_set) > 0
  end
  old_beers
end

def similarity(a, b)
  a.jarowinkler_similar(b)
end

def apply_rename_rules(name)
  rules = {
    /\bCo\.?(\s|$)/          => '\1',
    /\bCompany\.?(\s|$)/     => '\1',
    /\bL\.?L\.?C\.?(\s|$)/   => '\1',
    /\bInc\.?(\s|$)/         => '\1',
    /\bLtd\.?(\s|$)/         => '\1',
    /\bLimited(\s|$)/        => '\1',
    /\bS\.?A\.?(\s|$)/i      => '\1',
    /\bN\.?V\.?(\s|$)/i      => '\1',
    /\bB\.?V\.?(\s|$)/i      => '\1',
    /\bA\.?\s?S\.?(\s|$)/i      => '\1',
    /Brewing/i             => 'Brewery',
    /,/                    => '',
    /&/                    => 'and'
  }
  orig = name.dup
  rules.each do |rule, replacement|
    name.gsub!(rule, replacement)
  end
  puts "#{orig} -> #{name}"
  name
end

if $redis.scard('rated_old_beers') > 0
  rated_beer_ids = $redis.smembers('rated_old_beers')
else
  rated_beer_ids = fetch_old_rated_beers.map(&:id)
  puts "Caching IDs of #{rated_beer_ids.size} rated old beers"
  $redis.sadd('rated_old_beers', rated_beer_ids)
end

puts "Found #{rated_beer_ids.size} rated beers"

buckets = {
  :no_match => 0,
  :one_match => 0,
  :many_matches => 0
}

old_breweries = OldBrewery.joins(:beers).where('beers.id IN (?)', rated_beer_ids).pluck(:name).uniq
# puts old_breweries
puts "#{old_breweries.size} breweries with rated beers"

matched_breweries = Brewery.where('name IN (?)', old_breweries).pluck(:name)

unmatched_breweries = old_breweries - matched_breweries
new_brewery_names = Brewery.pluck(:name)

unmatched_breweries.map! { |n| apply_rename_rules(n) }
new_brewery_names.map! { |n| apply_rename_rules(n) }

unmatched_breweries.each do |old_brewery_name|
  t0 = Time.now

  best_match = new_brewery_names.max_by do |new_brewery_name|
    similarity(old_brewery_name, new_brewery_name)
  end

  elapsed = Time.now - t0
  score = similarity(old_brewery_name, best_match)
  puts "Matched '#{old_brewery_name}' with '#{best_match}' with score #{score} in #{elapsed} s"
end

# rated_beer_ids.each do |old_beer_id|
#   old_beer = OldBeer.includes(:brewery).find(old_beer_id)
#   matches = Beer.joins(:breweries).where(name: old_beer.name).where('breweries.name = ?', old_beer.brewery.name).group_by('breweries.name').having('COUNT(breweries.*) < 1')
  
#   if matches.count == 0
#     puts "#{old_beer.id}, #{old_beer.name}, #{old_beer.brewery.name}"
#   end
# end

# puts buckets.inspect
