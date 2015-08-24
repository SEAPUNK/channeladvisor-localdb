require! <[ winston ]>

class CALDB
    ({@db, @client, @logger}) ->
        @setLogger!

    setLogger: ->
        @logger ?= @makeDummyLogger!

    getLogger: -> @logger

    makeDummyLogger: ->
        new (winston.Logger) do
            transports: []


module.exports = CALDB