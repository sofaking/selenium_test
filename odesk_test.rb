require 'selenium-webdriver'
require 'logger'
require 'pry'

KEYWORD = ARGV[0] || 'ruby'
BROWSER = (ARGV[1] || 'firefox').to_sym

def wait_for(selector)
  wait = Selenium::WebDriver::Wait.new(timeout: 10)
  wait.until { @driver.find_element(selector) }
end

class Page
  def initialize(driver)
    @driver = driver
  end
end

class HomePage < Page
  def hire_freelancers
    $log.info "Following 'Hire Freelancers' link"
    @driver.find_element(link_text: 'Hire Freelancers').click
  end
end

class ProfileSearchPage < Page
  def seach_by(search_string)
    $log.info "Searching for '#{search_string}' keyword"
    wait_for(name: 'q')
    @driver.find_element(name: 'q').send_keys(search_string)
    @driver.find_element(class: 'oSearchSubmit').click
  end
end

class GenericProfilePage < Page
  def initialize(driver)
    super
    @tags_path         = ".//section[contains(@class,'oSkills')]"
  end

  def gather_attributes(section)
    name        = section.find_element(xpath: @name_xpath).text
    title       = section.find_element(xpath: @title_xpath).text
    description = section.find_element(xpath: @description_xpath).text.sub(/\s\sless$/, '').gsub(/\n+/, ' ')
    tags        = section.find_element(xpath: @tags_path).text.sub(/\sless$/, '').split(' ')

    {name: name, title: title, description: description, tags: tags}
  end

  def open_more_links(section)
    section.find_elements(xpath: ".//a[@class = 'oMore' or @class = 'oExpandText']").each(&:click)
  end
end

class SerpPage < GenericProfilePage
  def initialize(driver)
    super
    @name_xpath        = ".//a[@class='oLoadContractor']/span"
    @title_xpath       = ".//h3[contains(@itemprop,'role')]"
    @description_xpath = ".//section[contains(@class,'oContractorDescription')]/p[not(contains(@class,'oTruncated'))]"
  end

  def profiles
    $log.info "Collecting contractors' profiles from search results"
    @search_results = @driver.find_elements(xpath: "//ul[contains(@class,'oSearchResultsList')]/li")

    open_more_links

    @search_results.map do |contractor|
      gather_attributes(contractor)
    end
  end

  def open_more_links
    @search_results.each do |item|
      super(item)
    end
  end

  def links_to_full_profiles
    @links_to_full_profiles ||= @search_results.map do |profile|
      profile.find_element(xpath: ".//a[@class='oLoadContractor']")
    end
  end

  def open_random_profile
    $log.info "Opening full profile of randomly selected contractor"
    links_to_full_profiles[rand(links_to_full_profiles.size - 1)].click
  end
end

class ProfilePage < GenericProfilePage
  def initialize(driver)
    super
    @name_xpath        = ".//h1[@class='oH1Huge']"
    @title_xpath       = ".//h1[@class='oH2High']"
    @description_xpath = ".//section[@class='oOverview']//p[@itemprop='description']"
  end

  def profile
    $log.info "Collecting contractors' information from full profile page"
    wait_for(xpath: "//div[contains(@class,'oContractorDetails')]")
    @details = @driver.find_element(xpath: "//div[contains(@class,'oContractorDetails')]")

    open_more_links

    gather_attributes(@details)
  end

  def open_more_links
    super(@details)
  end
end

$log = Logger.new(STDOUT)
$log.formatter = proc do |severity, datetime, progname, msg|
  datetime = datetime.strftime('%Y-%m-%d %H:%M:%S')
  "[#{datetime}] #{severity}: #{msg}\n"
end

$log.info "Visiting odesk.com with #{BROWSER} browser"
@driver = Selenium::WebDriver.for BROWSER
@driver.navigate.to 'http://www.odesk.com'

home_page = HomePage.new(@driver)
profile_search_page = ProfileSearchPage.new(@driver)
serp_page = SerpPage.new(@driver)
profile_page = ProfilePage.new(@driver)

home_page.hire_freelancers
profile_search_page.seach_by(KEYWORD)
contractors = serp_page.profiles

$log.info "Checking if at least one attribute contains '#{KEYWORD}' keyword"
contractors.each do |contractor|
  unless contractor.values.any? { |attr| attr.to_s =~ /#{KEYWORD}/i }
    $log.warn "Profile of '#{contractor[:name]}' doesn't contain #{KEYWORD}" 
  end
end

serp_page.open_random_profile
full_profile = profile_page.profile

$log.info "Checking if info from search results matching full profile content"
selected_contractor = contractors.find { |contractor| contractor[:name] == full_profile[:name] }
unless full_profile == selected_contractor
  $log.warn "Agrrr, #{full_profile[:name]}'s full profile doesn't match a profile from serp" 
end

@driver.quit
$log.close
