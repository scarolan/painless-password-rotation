remark.macros.scale = function (percentage) {
    var url = this;
    return '<img src="' + url + '" style="width: ' + percentage + '" />';
  };
  var slideshow = remark.create({
    ratio: '4:3',
    highlightStyle: 'tomorrow-night-bright',
    highlightLines: 'true',
  });