require 'jrubyfx'
require 'jrubyfx-fxmlloader'
require 'uri'
require 'openssl'
require_relative 'hawk'

require_relative 'hawk_helper'

class HawkLoginController
  include JRubyFX::Controller
  fxml 'fxlogin.fxml'

  def initialize
    values = observable_array_list %w(Hawkular Metrics OpenShift)
    @FXMLModeBox.items = values

    ri = Hawk.remote_info
    @FXMLModeBox.value = ri[:mode]

    modeOpenshift = @FXMLModeBox.value_property.isEqualTo 'OpenShift'
    @UserLabel.text_property.bind Java::javafx.beans.binding.When.new(modeOpenshift)
      .then('Token')
      .otherwise('Username')
    @FXMLPasswordField.disable_property.bind modeOpenshift


    @FXMLUrlField.text = ri[:url] if @FXMLUrlField.text.empty?
    @FXMLLoginField.text = ri[:user] if @FXMLLoginField.text.empty?
    @FXMLPasswordField.text = ri[:password] if @FXMLPasswordField.text.empty?
    @FXMLTenantField.text = ri[:tenant] if @FXMLTenantField.text.empty?

  end

  def login # callback from the login button
    creds = case @FXMLModeBox.value
            when 'OpenShift'
              { :token => @FXMLLoginField.text}
            else
              { :username => @FXMLLoginField.text,
                :password => @FXMLPasswordField.text
              }
            end

    ri = Hawk.remote_info
    the_url = @FXMLUrlField.text
    the_url = the_url.chop if the_url.end_with? '/'
    ri[:url]=the_url
    ri[:user]=@FXMLLoginField.text
    ri[:password]=@FXMLPasswordField.text
    ri[:tenant]=@FXMLTenantField.text
    ri[:mode]=@FXMLModeBox.value



    enable_logging

    # We need to require those after potentially enable logging
    # as otherwise the requiring will aready set the logging
    # of the restclient.
    require 'hawkular/hawkular_client'
    require 'hawkular/metrics/metrics_client.rb'
    require_relative 'hawk_main_controller'


    hash = {}
    hash[:entrypoint] = URI(the_url).to_s # TODO: see https://github.com/hawkular/hawkular-client-ruby/issues/116
    hash[:credentials] = creds
    hash[:options] = { :tenant => @FXMLTenantField.text }

    hash[:options].store(:verify_ssl, OpenSSL::SSL::VERIFY_NONE)  if @Disable_SSL.selected

    begin
      if @FXMLModeBox.value == 'Hawkular'
        Hawk.client = ::Hawkular::Client.new(hash)
        Hawk.mode = :hawkular
      else # Metrics only mode
        Hawk.mode = :metrics
        Hawk.client = ::Hawkular::Client.new(hash)
        Hawk.metrics = Hawk.client.metrics
        Hawk.alerts = Hawk.client.alerts
      end

      # @tenant = $inventory_client.get_tenant
      @FXMLtextArea.text = "Tenant: #{@tenant}"

      show_main_pane

    rescue StandardError => e
      @FXMLtextArea.text = "Error: #{e}"
      @tenant = 'hawkular'
      raise e
    end
  end

  def enable_logging
    verbose = @logging_enabled.selected
    if verbose
      ENV['RESTCLIENT_LOG'] = 'stdout'
      ENV['HAWKULARCLIENT_LOG_RESPONSE'] = '1'
    end
  end

  # Now after login we can show the main app
  def show_main_pane
    dir = File.dirname(__FILE__).sub('/lib', '/assets/')

    # Create a Main controller, which will load fxml
    # into the passed stage
    main_controller = ::HawkMainController.load_into @stage, :width => 1000,
                                                            :height => 850,
                                                            :root_dir => dir

    @stage.min_width = 1000
    @stage.min_height = 800
    @stage.size_to_scene

    main_controller.show_initial_tree Hawk.mode
  end
end
