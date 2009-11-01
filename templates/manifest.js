/* Repertoire gem assets manifest file */

repertoire = repertoire || {}
repertoire.require = repertoire.require || {}
repertoire.require.js = function(src) {
  var script = document.createElement("script");
  script.type = "text/javascript";
  script.language = "javascript"; 
  script.src = src;
  document.getElementsByTagName("head")[0].appendChild(script);
}
repertoire.require.css = function(href) {
  var link = document.createElement("link");
  link.type = "text/css"; 
  link.rel = "stylesheet"; 
  link.href = href;
  document.getElementsByTagName("head")[0].appendChild(link);
}

<% manifest.each do |uri| %>
<% ext = uri[/\.(\w+)$/, 1] %>
repertoire.require.<%= ext %>('<%= uri %>');
<% end %>
