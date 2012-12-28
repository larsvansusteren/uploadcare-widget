# = require ./jquery.Jcrop

uploadcare.whenReady ->
  {
    namespace,
    jQuery: $
  } = uploadcare
  {tpl} = uploadcare.templates

  namespace 'uploadcare.crop', (ns) ->

    class ns.CropWidget

      defaultOptions =

        # DOM element or selector or jQuery object to which widget 
        # will be appended (required)
        container: null

        # URL of image to process (required)
        url: null

        # If set to `true` the resize method will be appended to result URL
        # like "-/resize/%preferedSize%/". (optional)
        scale: true

        # If set to `true` image in widget will be upscaled 
        # to widget size if necessary. (optional)
        upscale: false

        # Defines widget size. if set to `null` widget size will be equal 
        # the `container` size. Syntax: '123x123'. (optional)
        widgetSize: null

        # Defines image size you want to get at the end.
        # If `scale` option set to `false` it defines only prefered aspect ratio.
        # if set to `null` any aspect ratio will be acceptable.
        # Syntax: '123x123'. (optional)
        preferedSize: null

        # Specifies whether to show done button in widget or not. (optional)
        controls: true

      LOADING_ERROR = "loadingerror"

      CONTROLS_HEIGHT = 30

      checkOptions = (options) ->
        throw "options.container must be specified" unless options.container
        throw "options.url must be specified" unless options.url
        for option in ['widgetSize', 'preferedSize']
          value = options[option]
          unless !value or (typeof value is 'string' and value.match /^\d+x\d+$/i)
            throw "options.#{option} must follow pattern '123x456' or be falsy"
        if option.scale and not options.preferedSize
          throw "options.preferedSize must be specified if option.scale is true"

      fitSize = (objWidth, objHeight, boxWidth, boxHeight, upscale=false) ->
        if objWidth > boxWidth or objHeight > boxHeight or upscale
          if boxWidth / boxHeight < objWidth / objHeight
            newWidth = boxWidth
            newHeight = Math.floor objHeight / objWidth * newWidth
          else
            newHeight = boxHeight
            newWidth = Math.floor objWidth / objHeight * newHeight
        else
          newWidth = objWidth
          newHeight = objHeight
        [newWidth, newHeight]

      # Example:
      #   new CropWidget
      #     container: '.crop-widget-home'
      #     url: 'http://ucarecdn.com/%something%/'
      #     upscale: true
      #     widgetSize: '500x300'
      #     preferedSize: '100x100'
      constructor: (options) ->
        @__options = $.extend {}, defaultOptions, options
        checkOptions @__options
        @__buildWidget()
        @__bind()
        @__deferred = $.Deferred()
        @__setImage @__options.url

      # Example:
      #   cropWidget = new CropWidget( ... )
      #   cropWidget.croppedImageUrl()
      #     .done (url) ->
      #       # ...
      #     .fail (error) ->
      #       # ...
      croppedImageUrl: ->
        @__deferred.promise()

      # This method could be usefull if you want to make your own done button.
      forceDone: ->
        if @__currentCoords
          @__deferred.resolve @__buildUrl @getCurrentCoords()
        else
          throw "not ready"

      # Returns last selected area coords
      getCurrentCoords: ->
        scaleRatio = @__resizedWidth / @__originalWidth
        fixedCoords = {}
        for key, value of @__currentCoords
          fixedCoords[key] = Math.round value / scaleRatio
        fixedCoords

      # Destroys widget completly
      destroy: ->
        @__jCropApi.destroy()
        @__widgetElement.remove()
        @__widgetElement = @__imageWrap = @__doneButton = @__img = null
        @__currentCoords = null

      __buildUrl: (coords) ->
        topLeft = "#{coords.x}x#{coords.y}"
        bottomRight = "#{coords.x2}x#{coords.y2}"
        url = "#{@__options.url}-/custom_crop/#{topLeft}/#{bottomRight}/"
        if @__options.scale
          url += "-/resize/#{@__options.preferedSize}/"
        url

      __buildWidget: ->
        @container = $ @__options.container
        [@__wrapWidth, @__wrapHeight] = [@__widgetWidth, @__widgetHeight] = @__widgetSize()
        if @__options.controls
          @__wrapHeight -= CONTROLS_HEIGHT
        @__widgetElement = $ tpl('crop-widget')
        @__imageWrap = @__widgetElement.find '@uploadcare-crop-widget-image-wrap'
        @__doneButton = @__widgetElement.find '@uploadcare-crop-widget-done-button'
        unless @__options.controls
          @__widgetElement.addClass 'uploadcare-crop-widget--no-controls'
        @__imageWrap.css
          width: @__wrapWidth
          height: @__wrapHeight
        @__widgetElement.css
          width: @__widgetWidth
          height: @__widgetHeight
        @__widgetElement.appendTo @container

      __bind: ->
        @__doneButton.click =>
          @forceDone()

      __setImage: (@url) ->
        @__setState 'loading'
        @__img = $ "<img/>"
        @__img.attr
          src: @url
        @__img.on
          load: =>
            @__setState 'loaded'
            @__calcImgSizes()
            @__img.appendTo @__imageWrap
            @__initJcrop()
          error: =>
            @__setState 'error'
            @__deferred.reject LOADING_ERROR

      __calcImgSizes: ->
        @__originalWidth = @__img[0].width
        @__originalHeight = @__img[0].height
        [@__resizedWidth, @__resizedHeight] = 
          fitSize @__originalWidth, @__originalHeight, @__wrapWidth, @__wrapHeight, @__options.upscale
        @__img.attr
          width: @__resizedWidth
          height: @__resizedHeight
        paddingTop = (@__wrapHeight - @__resizedHeight) / 2
        paddingLeft = (@__wrapWidth - @__resizedWidth) / 2
        @__imageWrap.css {
          paddingTop, 
          paddingLeft,
          width: @__wrapWidth - paddingLeft,
          height: @__wrapHeight - paddingTop
        }

      __widgetSize: ->
        if !@__options.widgetSize
          [@container.width(), @container.height()]
        else
          @__options.widgetSize.split 'x'

      # error <- loading -> loaded
      __setState: (state) ->
        @__widgetElement
          .removeClass(("uploadcare-crop-widget--#{s}" for s in ['error', 'loading', 'loaded']).join ' ')
          .addClass("uploadcare-crop-widget--#{state}")
          .trigger("uploadcare.crop.statechange", state)
        @__doneButton.prop
          disabled: state != 'loaded'

      __initJcrop: ->
        jCropOptions =
          onSelect: (coords) => @__currentCoords = coords
        if @__options.preferedSize
          [width, height] = @__options.preferedSize.split 'x'
          jCropOptions.aspectRatio = width / height
          jCropOptions.setSelect = [0, 0, width, height]
        else
          jCropOptions.setSelect = [0, 0, @__resizedWidth, @__resizedHeight]
        setApi = (api) => @__jCropApi = api
        @__img.Jcrop jCropOptions, -> setApi this
