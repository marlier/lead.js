# types of github urls
#
# github.com
#   gist.github.com/also/5794205
#   gist.github.com/5794205.git
#   api.github.com/gists/5794205
#
# git.example.com
#   git.example.com/gist/1051
#   git.example.com/api/v3/gists/1051?access_token=...

define (require) ->
  URI = require 'URIjs'
  Q = require 'q'
  React = require 'react'
  modules = require 'modules'
  http = require 'http'
  global_settings = require 'settings'

  notebook = null
  require ['notebook'], (nb) ->
    notebook = nb

  modules.create 'github', ({fn, cmd, settings}) ->
    settings.set 'githubs', 'github.com', 'api_base_url', 'https://api.github.com'
    settings.default 'default', 'github.com'

    github =
      get_site_from_url: (url) ->
        uri = URI url
        hostname = uri.hostname()
        if hostname == 'gist.github.com' or hostname == 'api.github.com'
          host = 'github.com'
        else
          host = hostname

        github.get_site host

      default: -> settings.get 'default'
      get_site: (name) -> settings.get 'githubs', name ? settings.get 'default'

      get_repo_contents: (url) ->
        http.get(url)
        .then (response) ->
          file =
            content: atob response.content.replace /\n/g, ''
            filename: response.name
            type: 'application/octet-stream'
            base_href: response.html_url.replace '/blob/', '/raw/'

      to_repo_url: (path) ->
        path = path.toString()
        if path.indexOf('http') != 0
          site = github.get_site()
          path = path.substr 1 if path[0] == '/'
          [user, repo, segments...] = path.split '/'
          url = github.to_api_url site, "/repos/#{user}/#{repo}/contents/#{segments.join '/'}"
        else
          site = github.get_site_from_url path
          if path.indexOf(site.api_base_url) == 0
            url = URI path
          else
            uri = URI path
            path = uri.pathname()
            path = path.substr 1 if path[0] == '/'
            [user, repo, x, ref, segments...] = path.split '/'
            url = github.to_api_url site, "/repos/#{user}/#{repo}/contents/#{segments.join '/'}", {ref}

      save_gist: (gist, options={}) ->
        site = github.get_site options.github
        http.post github.to_api_url(site, '/gists'), gist

      update_gist: (id, gist, options={}) ->
        site = github.get_site options.github
        http.patch github.to_api_url(site, "/gists/#{id}"), gist

      to_api_url: (site, path, params={}) ->
        result = URI("#{site.api_base_url}#{path}").setQuery(params)
        result.setQuery('access_token', site.access_token) if site.access_token?
        result

      to_gist_url: (gist) ->
        build_url = (site, id) ->
          github.to_api_url site, "/gists/#{id}"
        gist = gist.toString()
        if gist.indexOf('http') != 0
          site = github.get_site()
          build_url site, gist
        else
          site = github.get_site_from_url gist

          if github?
            [id, rest...] = URI(gist).filename().split '.'
            build_url site, id
          else
            URI gist

    fn 'load', 'Loads a file from GitHub', (path, options={}) ->
      url = github.to_repo_url path
      @async ->
        authorized = ensure_access @, url
        authorized.then (url) =>
          @text "Loading file #{path}"
          promise = github.get_repo_contents(url)
          .then (file) =>
            notebook.handle_file @, file, options
          promise.fail (response) =>
            @error response.statusText
          promise

    ensure_access = (ctx, url) ->
      unless url?
        domain = github.default()
        site = github.get_site domain
      else
        site = github.get_site_from_url url
        domain = url.hostname()
      if site? and site.requires_access_token and not site.access_token?
        result = Q.defer()
        ctx.text 'Please set a GitHub access token:'
        input = ctx.input.text_input()
        button = ctx.input.button('Save')
        user_details = button.map(input).flatMapLatest (access_token) ->
          Bacon.combineTemplate
            user: Bacon.fromPromise http.get github.to_api_url(site, '/user').setQuery {access_token}
            access_token: access_token
          .changes()
        user_details.onValue ({user, access_token}) =>
          global_settings.user_settings.set 'github', 'githubs', domain, 'access_token', access_token
          ctx.text "Logged in as #{user.name}"
          result.resolve url?.setQuery {access_token}
        user_details.onError =>
          ctx.text "That access token didn't work. Try again?"
        result.promise
      else
        Q url

    cmd 'gist', 'Loads a script from a gist', (gist, options={}) ->
      if arguments.length is 0
        @github.save_gist()
      else
        url = github.to_gist_url gist
        @async ->
          authorized = ensure_access @, url
          authorized.then (url) =>
            @text "Loading gist #{gist}"
            promise = http.get url
            promise.done (response) =>
              @add_component GistLinkComponent gist: response
              for name, file of response.files
                notebook.handle_file @, file, options
            promise.fail (response) =>
              @error response.statusText

    GistLinkComponent = React.createClass
      render: ->
        avatar = @props.gist.user?.avatar_url ? 'https://github.com/images/gravatars/gravatar-user-420.png'
        username = @props.gist.user?.login ? 'anonymous'
        filenames = _.keys @props.gist.files
        filenames.sort()
        if filenames[0] == 'gistfile1.txt'
          title = "gist:#{@props.gist.id}"
        else
          title = filenames[0]
        React.DOM.div {className: 'gist-link'}, [
          React.DOM.img {src: avatar}
          if @props.gist.user?
            React.DOM.a {href: @props.gist.user.html_url, target: '_blank'}, username
          else
            username
          ' / '
          React.DOM.a {href: @props.gist.html_url, target: '_blank'}, title
          React.DOM.span {className: 'datetime'}, "Saved #{moment(@props.gist.updated_at).fromNow()}"
        ]

    NotebookGistLinkComponent = React.createClass
      render: ->
        lead_uri = URI window.location.href
        lead_uri.query null
        lead_uri.fragment "/#{@props.gist.html_url}"
        React.DOM.div {}, [
          GistLinkComponent gist: @props.gist
          # TODO should this be target=_blank
          React.DOM.p {}, React.DOM.a {href: lead_uri}, lead_uri.toString()
        ]

    cmd 'save_gist', 'Saves a notebook as a gist', (id) ->
      notebook = @export_notebook()
      gist =
        public: true
        files:
          'notebook.lnb':
            content: JSON.stringify notebook, undefined, 2
      @async ->
        authorized = ensure_access @
        authorized.then (url) =>
          promise = if id?
            github.update_gist id, gist
          else
            github.save_gist gist
          promise.done (result) =>
            @add_component NotebookGistLinkComponent gist: result
          promise.fail =>
            @error 'Save failed. Make sure your access token is configured correctly.'

    github
