module SlideshareIntegration

  ConfigPath = "config/slideshare_integration.yml".freeze

  # A list of content types supported by iPaper.
  ContentTypes = [
    'application/pdf',
    'application/msword',
    'application/mspowerpoint',
    'application/vnd.ms-powerpoint',
    'application/excel',
    'application/vnd.ms-excel',
    'application/postscript',
    'text/plain',
    'text/rtf',
    'application/rtf',
    'application/vnd.oasis.opendocument.text',
    'application/vnd.oasis.opendocument.presentation',
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.sun.xml.writer',
    'application/vnd.sun.xml.impress',
    'application/vnd.sun.xml.calc',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.template',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
    'application/vnd.openxmlformats-officedocument.presentationml.template',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.template'
  ]

  # Available parameters for the JS API
  # http://www.scribd.com/publisher/api/api?method_name=Javascript+API
  Available_JS_Params = [ :height, :width, :page, :my_user_id, :search_query,
                          :jsapi_version, :disable_related_docs, :mode, :auto_size, :hide_disabled_buttons, :hide_full_screen_button]

  class SlideshareIntegrationError < StandardError #:nodoc:
  end

  class SlideshareIntegrationUploadError < SlideshareIntegrationError #:nodoc:
  end


  class << self

    def included(base) #:nodoc:
      base.extend ClassMethods
    end

    def slideshare_object
        @slideshare = SlideShare::Base.new(api_key: config[:api_key], shared_secret: config[:shared_secret])
    end      

    # Login, store, and return a handle to the Scribd user account
    def slideshow
      begin
        @slideshow = slideshare_object.slideshows
      rescue
        raise SlideshareIntegrationError, "Your SlideShare credentials are incorrect"
      end
    end

    # Upload a file to Scribd
    def upload(obj, title, file_path, options = {})
      begin
        slideshow_id = slideshow.create(title, file_path, config[:user], config[:pass], Options)
        obj.update_attributes({:slideshow_id => slideshow_id})
      rescue
        raise SlideshareIntegrationUploadError, "Sorry, but #{obj.class} ##{obj.id} could not be uploaded to Scribd"
      end
    end

    # Delete an iPaper document
    def destroy(slidshow_id)
      slideshow.destroy(slideshow_id, config[:user], config[:pass])
    end

    # Read, store, and return the ScribdFu config file's contents
    def config
      path = defined?(Rails) ? File.join(Rails.root, ConfigPath) : ConfigPath
      raise SlideshareIntegrationError, "#{path} does not exist" unless File.file?(path)

      # Load the config file and strip any whitespace from the values
      @config ||= YAML.load_file(path).each_pair{|k,v| {k=>v.to_s.strip}}.symbolize_keys!
    end

    # Get the preferred access level for iPaper documents
    def access_level
      config[:access] || 'private'
    end

    # Load, store, and return the associated iPaper document
    def load_slideshow(slideshow_id)
      # Yes, catch-all rescues are bad, but the end rescue
      # should return nil, so laziness FTW.
      slideshow.find(slideshow_id) rescue nil
    end
  end

  module ClassMethods

    # Load and inject ScribdFu goodies
    # opts can be :on => :create, defaults to :on => :save
    def has_slideshare_and_uses(str, opts = {:on => :save })
      check_environment
      load_base_plugin(str)

      include InstanceMethods

      send("after_#{opts[:on]}", :upload_to_slideshare) # This *MUST* be an after_save
      before_destroy :destroy_slideshow
      attribute_accessor :slideshow_title, :slideshow_options
    end

    private

      # Configure ScribdFu for this particular environment
      def check_environment
        check_config
      end

      def check_config
        SlideshareIntegration::config
      end

      # Load Paperclip specific methods and files
      def load_paperclip
        require 'slideshare_integration/paperclip'
        include SlideshareIntegration::Paperclip::InstanceMethods
      end

      # Load either AttachmentFu or Paperclip-specific methods
      def load_base_plugin(str)
        if str == 'Paperclip'
          load_paperclip
        else
          raise SlideshareIntegrationError, "Sorry, only Attachment_fu and Paperclip are supported."
        end
      end

  end

  module InstanceMethods

    def self.included(base)
      base.extend ClassMethods
    end

    # Upload the associated file to Scribd for iPaper conversion
    # This is called +after_save+ and cannot be called earlier,
    # so don't get any ideas.
    def upload_to_slideshare
      SlideshareIntegation::upload(self, slideshow_title, file_path, slideshow_options) if scribdable?
    end

    # Checks whether the associated file is convertable to iPaper
    def scribdable?
      ContentTypes.include?(get_content_type) && slideshow_id.blank?
    end

    # Responds the Slideshare::Document associated with this model, or nil if it does not exist.
    def slideshow
      @slideshow ||= SlideshareIntegration::load_slideshow(slideshow_id)
    end

    # Destroys the slideshare document for this record. This is called +before_destroy+
    def destroy_slideshow
      SlideshareIntegration::destroy(slideshow) if slideshow
    end

    # Display the iPaper document in a view
    def display_slideshow(options = {})
      id = options.delete(:id)
      <<-END
        <iframe class="scribd_iframe_embed" src="http://www.scribd.com/embeds/#{ipaper_id}/content?start_page=1&view_mode=slideshow&access_key=#{ipaper_access_key}" data-auto-height="true" scrolling="no" id="scribd_#{ipaper_id}" width="100%" frameborder="0"></iframe><script type="text/javascript">(function() { var scribd = document.createElement("script"); scribd.type = "text/javascript"; scribd.async = true; scribd.src = "http://www.scribd.com/javascripts/embed_code/inject.js"; var s = document.getElementsByTagName("script")[0]; s.parentNode.insertBefore(scribd, s); })();</script>
      END
    end

  end

end

# Let's do this.
ActiveRecord::Base.send(:include, SlideshareIntegration) if Object.const_defined?("ActiveRecord")

