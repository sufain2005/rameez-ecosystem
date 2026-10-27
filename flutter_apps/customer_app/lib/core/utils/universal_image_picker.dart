import 'dart:js' as js;

/// Universal Direct Image / Photo Upload Helper for Flutter (Web, Mobile, Laptop)
/// Opens device camera or native file selector, converts to base64, and uploads to `/api/upload`.
class UniversalImagePicker {
  static void pickImage({
    String? captureMode, // 'camera' or null for files/gallery
    required void Function(String imageUrl, String fileName) onSelected,
  }) {
    try {
      js.context['__activeCustomerPhotoCallback'] =
          js.JsFunction.withThis((_, dynamic url, dynamic name) {
        if (url != null) {
          onSelected(url.toString(), name?.toString() ?? 'customer_avatar.jpg');
        }
      });

      js.context.callMethod('eval', [
        '''
        (function() {
          var input = document.createElement('input');
          input.type = 'file';
          input.accept = 'image/*';
          ${captureMode == 'camera' ? "input.capture = 'user';" : ""}
          input.style.display = 'none';
          document.body.appendChild(input);

          input.onchange = function(e) {
            var file = e.target.files[0];
            if (!file) {
              if (input.parentNode) document.body.removeChild(input);
              return;
            }
            var reader = new FileReader();
            reader.onload = function(evt) {
              var base64Data = evt.target.result;
              if (input.parentNode) document.body.removeChild(input);
              var backendUrl = 'https://rameez-kitchen-backend.onrender.com/api/upload';
              fetch(backendUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ image: base64Data, name: file.name })
              })
              .then(function(r) { return r.json(); })
              .then(function(j) {
                if (window.__activeCustomerPhotoCallback) {
                  window.__activeCustomerPhotoCallback(j.url || base64Data, file.name);
                }
              })
              .catch(function(err) {
                if (window.__activeCustomerPhotoCallback) {
                  window.__activeCustomerPhotoCallback(base64Data, file.name);
                }
              });
            };
            reader.readAsDataURL(file);
          };
          input.click();
        })()
        '''
      ]);
    } catch (_) {}
  }
}
