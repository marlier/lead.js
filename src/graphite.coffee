define (require) ->
  _ = require 'underscore'
  $ = require 'jquery'
  bacon = require 'baconjs'
  Q = require 'q'
  URI = require 'URIjs'
  moment = require 'moment'
  React = require 'react_abuse'
  dsl = require 'dsl'
  modules = require 'modules'
  function_names = require 'functions'
  http = require 'http'
  docs = require 'graphite_docs'
  parser = require 'graphite_parser'
  builtins = require 'builtins'
  Html = require 'html'
  Documentation = require 'documentation'

  graphite = modules.create 'graphite', ({fn, component_fn, cmd, settings}) ->
    build_function_doc = (ctx, doc) ->
      FunctionDocsComponent {ctx, docs: docs.function_docs[doc.function_name]}

    build_parameter_doc = (ctx, doc) ->
      ParameterDocsComponent {ctx, docs: docs.parameter_docs[doc.parameter_name]}

    _.each docs.function_docs, (d, n) ->
      Documentation.register_documentation ['graphite_functions', n], function_name: n, summary: d.signature, complete: build_function_doc

    _.each docs.parameter_docs, (d, n) ->
      Documentation.register_documentation ['graphite_parameters', n], parameter_name: n, summary: 'A Graphite parameter', complete: build_parameter_doc

    Documentation.register_documentation 'graphite_functions', index: true
    Documentation.register_documentation 'graphite_parameters', index: true

    args_to_params = (context, args) ->
      graphite.args_to_params {args, default_options: context.options()}

    default_target_command = 'img'

    fn 'q', 'Escapes a Graphite metric query', (targets...) ->
      for t in targets
        unless _.isString t
          throw new TypeError "#{t} is not a string"
      @value new dsl.type.q targets.map(String)...

    FunctionDocsComponent = React.createClass
      render: ->
        React.DOM.div {}, [
          React.DOM.div dangerouslySetInnerHTML: __html: @props.docs.docs
          _.map @props.docs.examples, (example) =>
            builtins.ExampleComponent ctx: @props.ctx, value: "#{default_target_command} #{JSON.stringify example}", run: false
        ]

    ParameterDocsComponent = React.createClass
      render: -> React.DOM.div()
      componentDidMount: (node) ->
        ctx = @props.ctx
        # TODO
        $docs = $(node).append @props.docs
        $docs.find('a').on 'click', (e) ->
          e.preventDefault()
          href = $(this).attr 'href'
          if href[0] is '#'
            ctx.run "docs '#{decodeURI href[1..]}'"

    cmd 'docs', 'Shows the documentation for a Graphite function or parameter', (name) ->
      if name?
        name = name.to_js_string() if name.to_js_string?
        name = name._lead_context_fn?.name if name._lead_op?
        function_docs = docs.function_docs[name]
        if function_docs?
          @help "graphite_functions.#{name}"
        name = docs.parameter_doc_ids[name] ? name
        parameter_docs = docs.parameter_docs[name]
        if parameter_docs?
          @help "graphite_parameters.#{name}"
        unless function_docs? or parameter_docs?
          @text 'Documentation not found'
      else
        @add_component React.DOM.h3 {}, 'Functions'
        @help 'graphite_functions'

        @add_component React.DOM.h3 {}, 'Parameters'
        @help 'graphite_parameters'

    fn 'params', 'Generates the parameters for a Graphite render call', (args...) ->
      result = args_to_params @, args
      @value result

    component_fn 'url', 'Generates a URL for a Graphite image', (args...) ->
      params = args_to_params @, args
      url = graphite.render_url params
      React.DOM.pre {}, React.DOM.a {href: url, target: 'blank'}, url

    fn 'img', 'Renders a Graphite graph image', (args...) ->
      params = args_to_params @, args
      url = graphite.render_url params
      @async ->
        # TODO move this to react once it supports onload and onerror
        # https://github.com/facebook/react/pull/774
        $img = $ "<img src='#{url}'/>"
        @div $img
        deferred = Q.defer()
        $img.on 'load', deferred.resolve
        $img.on 'error', deferred.reject

        promise = deferred.promise
        promise.fail (args...) =>
          @error 'Failed to load image'
        promise

    TimeSeriesTable = React.createClass
      render: ->
        React.DOM.table {}, _.map @props.datapoints, ([value, timestamp]) ->
          time = moment(timestamp * 1000)
          React.DOM.tr {}, [
            React.DOM.th {}, time.format 'MMMM Do YYYY, h:mm:ss a'
            React.DOM.td {className: 'cm-number number'}, value?.toFixed(3) or '(none)'
          ]

    TimeSeriesTableList = React.createClass
      render: ->
        React.DOM.div {}, _.map @props.serieses, (series) ->
          React.DOM.div {}, [
            React.DOM.h3 {}, series.target
            TimeSeriesTable datapoints: series.datapoints
          ]

    fn 'table', 'Displays Graphite data in a table', (args...) ->
      params = args_to_params @, args
      @async ->
        result = React.PropsHolder constructor: TimeSeriesTableList, props: serieses: []
        @add_component result
        promise = graphite.get_data params
        promise.then (response) =>
          result.set_child_props serieses: response
        .fail (error) =>
          @error error
          Q.reject error
        promise

    fn 'browser', 'Browse Graphite metrics using a wildcard query', (query) ->
      finder = @graphite.find query
      finder.clicks.onValue (node) =>
        if node.is_leaf
          @run "q(#{JSON.stringify node.path})"
        else
          @run "browser #{JSON.stringify node.path + '*'}"
      @add_renderable finder

    FindResultsComponent = React.createClass
      render: ->
        query_parts = @props.query.split '.'
        React.DOM.ul {className: 'find-results'}, _.map @props.results, (node) =>
          text = node.path
          text += '*' unless node.is_leaf
          node_parts = text.split '.'
          React.DOM.li {className: 'cm-string', onClick: => @props.on_click node}, _.map node_parts, (segment, i) ->
            s = segment
            s = '.' + s unless i == 0
            React.DOM.span {className: if segment == query_parts[i] then 'light' else null}, s

    fn 'find', 'Finds Graphite metrics', (query) ->
      promise = graphite.find query
      promise.clicks = new Bacon.Bus

      @value @renderable promise, @detached -> @async ->
        result = React.PropsHolder constructor: FindResultsComponent, props: {results: [], query, on_click: (node) -> promise.clicks.push node}
        @add_component result
        promise.then (r) =>
          result.set_child_props results: r.result
        .fail (reason) =>
          @error 'Find request failed'
          Q.reject reason
        promise

    fn 'get_data', 'Fetches Graphite metric data', (args...) ->
      @value graphite.get_data graphite.args_to_params {args, default_options: @options()}

    context_vars: -> dsl.define_functions {}, function_names

    init: ->
      # TODO there's no way for this to be set by the time we get here
      if settings.get 'define_parameters'
        _.map docs.parameter_docs, (v, k) ->
          fn k, "Gets or sets Graphite parameter #{k}", (value) ->
            if value?
              @current_options[k] = value
            else
              @value @current_options[k] ? @default_options[k]

    is_pattern: (s) ->
      for c in '*?[{'
        return true if s.indexOf(c) >= 0
      false

    url: (path, params) ->
      base_url = settings.get 'base_url'
      if not base_url?
        throw new Error 'Graphite base_url not set'
      query_string = $.param params, true
      "#{base_url}/#{path}?#{query_string}"

    render_url: (params) -> graphite.url 'render', params

    parse_target: (string) -> parser.parse string

    parse_url: (string) ->
      url = new URI string
      query = url.query true
      targets = query.target or []
      targets = [targets] unless _.isArray targets
      targets: _.map targets, graphite.parse_target
      options: _.omit query, 'target'

    parse_error_response: (response) ->
      return 'request failed' unless response.responseText?
      html = Html.parse_document response.responseText
      pre = html.querySelector 'pre.exception_value'
      if pre?
        # python debug error message
        h1 = html.querySelector 'h1'
        msg = "#{h1.innerText}: #{pre.innerText}"
      else
        # graphite style error message in a pre
        pre = html.querySelector 'pre'
        msg = pre.innerText.trim()
      msg ? 'Unknown error'

    parse_find_response: (query, response) ->
      parts = query.split '.'
      pattern_parts = parts.map graphite.is_pattern
      list = (node.path for node in response)
      patterned_list = for path in list
        result = for matched, i in path.split '.'
          if pattern_parts[i]
            parts[i]
          else
            matched
        result.join '.'
      _.uniq patterned_list.concat(list)

    transform_response: (response) ->
      if settings.get('type') == 'lead'
        _.map response, ({name, start, step, values}) ->
          target: name
          datapoints: _.map values, (v, i) ->
            [v, start + step * i]
      else
        response


    # returns a promise
    get_data: (params) ->
      params.format = 'json'
      deferred = http.get graphite.render_url params

      deferred.then graphite.transform_response, (response) -> Q.reject graphite.parse_error_response response

    # returns a promise
    complete: (query) ->
      graphite.find(query + '*')
      .then ({result}) ->
        if settings.get('type') == 'lead'
          for n in result
            n.path += '.' unless n.is_leaf
        graphite.parse_find_response query, result

    find: (query) ->
      if settings.get('type') == 'lead'
        http.get(graphite.url 'find', query: encodeURIComponent query).then (response) ->
          result = _.map response, (m) -> {path: m.name, name: m.name, is_leaf: m['is-leaf']}
          {query, result}
      else
        params =
          query: encodeURIComponent query
          format: 'completer'
        http.get(graphite.url 'metrics/find', params)
        .then (response) ->
          result = _.map response.metrics, ({path, name, is_leaf}) -> {path, name, is_leaf: is_leaf == '1'}
          {query, result}

    suggest_keys: (s) ->
      _.filter _.keys(docs.parameter_docs), (k) -> k.indexOf(s) is 0

    args_to_params: ({args, default_options}) ->
      if args.legnth == 0
        # you're doing it wrong
        {}
      if args.length == 1
        arg = args[0]
        targets = arg.targets ? arg.target
        if targets?
          if arg.options
            options = arg.options
          else
            options = _.clone arg
            delete options.targets
            delete options.target
        else
          targets = args[0]
          options = {}
      else
        last = args[args.length - 1]

        if _.isString(last) or dsl.is_dsl_node(last) or _.isArray last
          targets = args
          options = {}
        else
          [targets..., options] = args

      targets = [targets] unless _.isArray targets
      # flatten one level of nested arrays
      targets = Array.prototype.concat.apply [], targets

      params = _.extend {}, default_options, options
      params.target = (dsl.to_target_string(target) for target in targets)
      params

    has_docs: (name) ->
      docs.parameter_docs[name]? or docs.parameter_doc_ids[name]? or docs.function_docs[name]?

  graphite.suggest_strings = graphite.complete

  graphite

