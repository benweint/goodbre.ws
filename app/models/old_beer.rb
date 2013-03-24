class OldBeer < ActiveRecord::Base
  include Permalinkable
  include Socialable

  self.table_name = :beers

  establish_connection(:old)

  has_and_belongs_to_many :ingredients
  belongs_to :brewery, :class_name => 'OldBrewery', :foreign_key => 'brewery_id'
  belongs_to :style

  def self.paginate(options = {})
    page(options[:page]).per(options[:per_page])
  end
end
