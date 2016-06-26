#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'ostruct'

## Config
Bundler.require
HTTPI.adapter = :curb
Octokit.auto_paginate = true

def ask(q)
  print q + ': '
  response = gets.chomp!
end

## Gather info from user
jira_subdomain = ask("Atlassian OnDemand Subdomain")
jira_username = ask("Atlassian Username")
jira_password = ask("Atlassian Password")

github_org = ask("Github Org")
github_token = ask("Github API token [need scopes: admin:repo_hook,repo]")

## fetch Jira repo data
request = HTTPI::Request.new "https://#{jira_subdomain}.atlassian.net/rest/bitbucket/1.0/repositories"
request.auth.basic(jira_username, jira_password)
response = HTTPI::get(request)

parser = Nori.new(:convert_tags_to => lambda { |tag| tag.snakecase.to_sym })
data = Hashie::Mash.new(parser.parse(response.body))

jira_repositories = data.repositories.repositories.inject do |memo, repo|
  memo[repo.repository_url.gsub("https://github.com/#{github_org}/", '')] = repo.id
  memo
end


## fetch github repos
client = Octokit::Client.new(:access_token => github_token)

client.org_repositories(github_org, :type => 'private').each do |repo|

  puts "adding webhooks to #{repo.name}..."

  jira_id = jira_repositories[repo.name]

  next unless jira_id

  jira_hook = "https://#{jira_subdomain}.atlassian.net/rest/bitbucket/1.0/repository/#{jira_id}/sync"

  repo_name = "#{github_org}/#{repo.name}"

  existing_hooks = client.hooks(repo_name)

  ###
  ### as per https://confluence.atlassian.com/jirakb/slow-appearing-commits-from-bitbucket-or-github-in-jira-779160823.html
  ###

  #
  # event #1
  #
  # only push event, form encoded
  #
  unless client.hooks(repo_name).detect {|x| x.name == 'web' && x.config.url == jira_hook && x.events == ["push"] && x.config.content_type == 'form'}
    client.create_hook(
      repo_name,
      "web",
      {
        :url => jira_hook,
        :content_type => "form"
      },
      {
        :events => ["push"],
        :active => true
      }
    )
  end

  #
  # event #2
  #
  # multiple events, json encoded
  #
  unless client.hooks(repo_name).detect {|x| x.name == 'web' && x.config.url == jira_hook && x.events == ["issue_comment", "pull_request", "pull_request_review_comment", "push"] && x.config.content_type == 'json'}
    client.create_hook(
      repo_name,
      "web",
      {
        :url => jira_hook,
        :content_type => "json"
      },
      {
        :events => ["issue_comment", "pull_request", "pull_request_review_comment", "push"],
        :active => true
      }
    )
  end

end
