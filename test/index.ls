require! 'chai'

{assert, expect} = chai

chai.should!

require! '../src/index':CALDB

describe \CALDB, ->
    describe \#construct, ->
        specify 'should NOT construct without any parameters', (done) ->
            try
                new CALDB
                done new Error "it constructed"
            catch e
                done!

        specify 'should construct with a good `opts` argument', ->
            new CALDB do
                db: {}
                client: {}
                logger: {}

        specify 'should use the winston logger we provide it', (done) ->
            db = new CALDB do
                db: {}
                client: {}
                logger:
                    info: ->
                        throw "ok"
            try
                db.getLogger! .info!
                done new Error "it seems to have used its dummy logger"
            catch e
                if e is "ok"
                    done!
                else
                    done e

        specify 'should use a dummy logger if no logger is specified', ->
            db = new CALDB do
                db: {}
                client: {}
            db.getLogger! .info 'test'

        #TODO: Test if CALDB's dummy logger is actually a dummy.
        #   We need to somehow monitor the console, and see if it
        #   outputs a string we don't want it to