require 'forwardable'
require 'pstore'
require 'pathname'
require 'uuid'

require 'sinatra'
require 'hexp'

TEMPLATES = {}
ROOT  = Pathname(__FILE__).join('..')

################################################################################
#
# Models

Post = Struct.new(:uuid, :title, :body, :timestamp)

module Store
  STORE = PStore.new(ROOT.join('hexp-blog.pstore'))
  STORE.transaction { STORE[:posts] ||= {} }

  class << self
    def save_post(post)
      STORE.transaction do
        STORE[:posts][post.uuid] = post
      end
    end

    def posts
      STORE.transaction(true) { STORE[:posts].values }
    end

    def find_post(uuid)
      STORE.transaction(true) { STORE[:posts][uuid] }
    end
  end
end

def Post.create(attrs)
  Store.save_post(
    Post.new(
      attrs.fetch('uuid') { SecureRandom.uuid },
      attrs.fetch('title').to_s,
      attrs.fetch('body').to_s,
      attrs.fetch('timestamp') { Time.now }
    )
  )
end

def Post.find(uuid)
  Store.find_post(uuid)
end

def Post.all
  Store.posts
end

################################################################################
#
# Views
#

def template(name)
  TEMPLATES[name] ||= Hexp.parse(IO.read(ROOT.join(name + '.html')))
end

def layout
  template('layout').replace('#main') do |main|
    main << yield.to_hexp
  end.to_html(html5: true)
end

def render_post(post, template)
  template
    .replace('.post-title') {|h| h << post.title }
    .replace('.post-body')  {|h| h << post.body  }
    .replace('.post-permalink') {|h| h.attr('href', "/post/#{post.uuid}") }
end

class Sinatra::Application
  extend Forwardable
  def_delegator Hexp, :build
end

################################################################################
#
# Controllers
#

get '/post' do
  layout {
    build('div') {
      h1 "Create a post"
      form(action: '/post', method: 'POST') {
        label 'Title', for: 'title'
        input type: 'text', name: 'title'
        textarea name: 'body'
        input type: 'submit'
      }
    }
  }
end

post '/post' do
  Post.create(params)
  redirect '/'
end

get '/' do
  layout {
    template('post_listing').replace('.post') do |templ|
      Post.all.map {|post| render_post(post, templ) }
    end
  }
end

get '/post/:uuid' do
  layout {
    template('single_post').replace('.post') do |templ|
      render_post Post.find(params['uuid']), templ
    end
  }
end
