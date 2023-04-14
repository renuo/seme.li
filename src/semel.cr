require "kemal"
require "./storage"

serve_static false

storage = Storage.new(ENV["KEMAL_ENV"]? || "development")
MAX_EXPIRES_IN_SECONDS = 60 * 60 * 24 * 30 # 30 days
MAX_CIPHERTEXT_LENGTH = 1_401 # Length of first illegal prime number, see https://t5k.org/curios/page.php?number_id=953

before_all do |env|
  env.response.headers["Access-Control-Allow-Origin"] = "*"

  # CSP rules are quite loose because 'self' is not allowed. If shit happens, then it's your browser (or extensions).
  env.response.headers["Content-Security-Policy"] = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src 'none';"
end

get "/" do
  render "src/views/new.ecr", "src/views/layout.ecr"
end

get "/try" do
  render "src/views/try.ecr", "src/views/layout.ecr"
end

post "/create" do |env|
  env.response.content_type = "application/json"

  ciphertext = env.params.json["ciphertext"].as(String)
  expires_in_seconds = env.params.json["expires_in_seconds"].as(Int64)

  if ciphertext.size > MAX_CIPHERTEXT_LENGTH
    halt env, status_code: 400, response: ({ errors: [{ status: "400", detail: "Maximum #{MAX_CIPHERTEXT_LENGTH} characters allowed." }] }.to_json)
  end

  if expires_in_seconds > MAX_EXPIRES_IN_SECONDS
    halt env, status_code: 400, response: ({ errors: [{ status: "400", detail: "Maximum expiriy time is #{MAX_EXPIRES_IN_SECONDS} seconds." }] }.to_json)
  end

  secret_id = storage.put(ciphertext, Time.utc.to_unix + expires_in_seconds)

  { url: "https://#{env.request.headers["Host"]}/try##{secret_id}" }.to_json
end

delete "/consume/:id" do |env|
  env.response.content_type = "application/json"

  storage.cut
  secret_id = env.params.url["id"].as(String)
  ciphertext = storage.consume(secret_id)

  unless ciphertext
    halt env, status_code: 404, response: ({ errors: [{ status: "404", detail: "Secret never existed or already gone." }] }.to_json)
  end

  { ciphertext: ciphertext }.to_json
end

get "/robots.txt" do |env|
  env.response.content_type = "text/plain; charset=utf-8"

  <<-STRING
  user-agent: *
  Allow: /$
  Disallow: /
  STRING
end

Kemal.run
