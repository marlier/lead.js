define (require) ->
  CoffeeScript = require 'coffee-script'
  Editor = require 'editor'
  Context = require 'context'

  recompile = (error_marks, editor) ->
    m.clear() for m in error_marks
    editor.clearGutter 'error'
    try
      CoffeeScript.compile editor.getValue()
      []
    catch e
      [Editor.add_error_mark editor, e]

  # gets the function for a cell
  # TODO rename
  get_fn = (run_context) ->
    create_fn run_context.input_cell.editor.getValue()

  # create the function for a string
  # this is exposed for cases where there is no input cell
  create_fn = (string) ->
    ->
      try
        compiled = CoffeeScript.compile(string, bare: true) + "\n//@ sourceURL=console-coffeescript.js"
        @scoped_eval compiled
      catch e
        if e instanceof SyntaxError
          @error "Syntax Error: #{e.message} at #{e.location.first_line + 1}:#{e.location.first_column + 1}"
        else
          console.error e.stack
          @error printStackTrace({e}).join('\n')
          @text 'Compiled JavaScript:'
          @source 'javascript', compiled

  {recompile, get_fn, create_fn}
