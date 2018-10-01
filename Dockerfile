FROM ruby:2.4.4
WORKDIR /app  
ADD . /app 
ADD ./Gemfile /app 
ADD ./Gemfile.lock /app
RUN bundle 
ENTRYPOINT ["ruby", "./lib/runners/lease_export.rb"]
