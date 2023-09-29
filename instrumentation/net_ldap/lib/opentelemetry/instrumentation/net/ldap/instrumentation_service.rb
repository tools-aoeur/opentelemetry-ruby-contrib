# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module Instrumentation
    module Net
      module LDAP
        # instrumentation service for ldap
        class InstrumentationService
          def initialize(args = {})
            @host = args[:host]
            @port = args[:port]
            @hosts = args[:hosts]
            @auth = args[:auth]
            @base = args[:base]
            @encryption = args[:encryption]
          end

          def instrument(event, payload)
            attributes = {
              'ldap.auth' => auth.except(:password).to_json,
              'ldap.base' => base,
              'ldap.encryption' => encryption.to_json,
              'ldap.payload' => payload.to_json,
              OpenTelemetry::SemanticConventions::Trace::NET_PEER_NAME => host || hosts,
              OpenTelemetry::SemanticConventions::Trace::NET_PEER_PORT => port,
              OpenTelemetry::SemanticConventions::Trace::PEER_SERVICE => instrumentation_config[:peer_service]
            }.merge!(OpenTelemetry::Common::HTTP::ClientContext.attributes)

            tracer.in_span(
              event,
              attributes: attributes.compact,
              kind: :client
            ) do |span|
              yield(payload).tap do |response|
                annotate_span_with_response!(span, response)
              end
            rescue StandardError => e
              span.set_attribute('ldap.error_message', "#{e.class}: #{e.message}")
              span.status = OpenTelemetry::Trace::Status.error
              raise e
            end
          end

          private

          attr_reader :host, :port, :hosts, :auth, :base, :encryption

          def tracer
            LDAP::Instrumentation.instance.tracer
          end

          def instrumentation_config
            LDAP::Instrumentation.instance.config
          end

          def annotate_span_with_response!(span, response)
            return unless response

            status_code = nil
            message = nil
            error_message = nil
            successful = true

            result = response.result if response.is_a?(::Net::LDAP::PDU)

            if [true, false].include?(response)
              successful = response
              status_code = ::Net::LDAP::ResultCodeSuccess if successful
            elsif result.is_a?(Hash)
              status_code = (result[:resultCode] || '').to_i
              message = ::Net::LDAP.result2string(status_code)
              error_message = result[:errorMessage].to_s
            else
              status_code = ::Net::LDAP::ResultCodeSuccess
            end

            span.set_attribute('ldap.status_code', status_code)
            span.set_attribute('ldap.message', message) if message
            span.set_attribute('ldap.error_message', error_message) unless error_message.to_s.empty?
            span.status = OpenTelemetry::Trace::Status.error if !successful || error_message
          end
        end
      end
    end
  end
end
