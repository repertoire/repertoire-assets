/* Repertoire gem assets manifest file */
(function() {
  
  function require_js(src, callback) {
    var script = document.createElement("script"),
        head   = document.getElementsByTagName("head")[0],
        done   = false;
    script.type = "text/javascript";
    script.language = "javascript"; 
    script.src = src;
    if (callback) {
      script.onload = script.onreadystatechange = function() {
        if (!done && (!this.readyState || this.readyState == "loaded" || this.readyState == "complete")) {
          done = true; 
          callback();
          head.removeChild(script);
        }
      }
    }
    head.appendChild(script);
  }
  
  function require_css(href) {
    var link = document.createElement("link");
    link.type = "text/css"; 
    link.rel = "stylesheet"; 
    link.href = href;
    document.getElementsByTagName("head")[0].appendChild(link);
  }
  
  function depend_js(list) {
    if (list.length > 0) {
      var src = list.shift();
      require_js(src, function() {
        depend_js(list);
      });
    }
    return list;
  };

  <% manifest.grep(/\.css$/) do |uri| -%>
  require_css('<%= uri %>');
  <% end -%>

  var list = depend_js(<%= manifest.grep(/\.js$/).to_json %>);
  
  while (list.length > 0) { /* block until loads finish */ }
})();