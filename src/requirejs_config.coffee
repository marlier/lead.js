@require =
  deps: ['bootstrap']
  paths:
    lib: '../lib'
    cm: '../lib/codemirror-3.21'
    underscore: '../lib/underscore'
    jquery: '../lib/jquery'
    d3: '../lib/d3.v3'
    URIjs: '../lib/URI'
    'stacktrace-js': '../lib/stacktrace-min-0.4'
    domReady: '../lib/domReady'
    baconjs: '../lib/Bacon'
    'bacon.model': '../lib/bacon.model'
    q: '../lib/q'
    moment: '../lib/moment'
    marked: '../lib/marked'
    'coffee-script': '../lib/coffee-script'
    react: '../lib/react-0.8.0'
    colorbrewer: '../lib/colorbrewer'
    'graphite_docs': '../lib/graphite_docs'
  shim:
    URIjs: ['bootstrap']
    'cm/codemirror':
        exports: 'CodeMirror'
    'cm/javascript': ['cm/codemirror']
    'cm/coffeescript': ['cm/codemirror']
    'cm/runmode': ['cm/codemirror']
    'cm/show-hint': ['cm/codemirror']
    'cm/markdown': ['cm/codemirror']
    'cm/gfm': ['cm/gfm']
    'jquery':
      exports: 'jQuery'
    'baconjs':
      deps: ['jquery']
    'd3':
      exports: 'd3'
    'colorbrewer':
      exports: 'colorbrewer'
    'underscore':
      exports: '_'
    'stacktrace-js':
      exports: 'printStackTrace'
