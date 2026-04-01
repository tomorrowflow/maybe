# Dynamic settings the user can change within the app (helpful for self-hosting)
class Setting < RailsSettings::Base
  cache_prefix { "v1" }

  field :synth_api_key, type: :string, default: ENV["SYNTH_API_KEY"]
  field :openai_access_token, type: :string, default: ENV["OPENAI_ACCESS_TOKEN"]
  field :ollama_host, type: :string, default: ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
  field :ollama_model, type: :string, default: ENV.fetch("OLLAMA_MODEL", "llama3.2")

  field :require_invite_for_signup, type: :boolean, default: false
  field :require_email_confirmation, type: :boolean, default: ENV.fetch("REQUIRE_EMAIL_CONFIRMATION", "true") == "true"

  field :eurostat_enabled, type: :boolean, default: ENV.fetch("EUROSTAT_ENABLED", "false") == "true"
  field :eurostat_default_region, type: :string, default: ENV.fetch("EUROSTAT_DEFAULT_REGION", "EU")

  field :retirement_target_age, type: :integer, default: ENV.fetch("RETIREMENT_TARGET_AGE", "90").to_i
  field :retirement_target_savings, type: :integer, default: ENV.fetch("RETIREMENT_TARGET_SAVINGS", "50000").to_i
end
