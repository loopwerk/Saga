---
template: home.html
---
#  Home
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer rutrum augue urna, a finibus eros hendrerit sed. Morbi semper commodo orci, et fringilla odio lacinia nec. Duis id augue quis leo tincidunt tincidunt eget a quam. Ut molestie mi blandit felis accumsan efficitur. Aliquam mauris erat, fermentum vitae nulla in, dapibus malesuada nibh. Ut vulputate libero quis ligula suscipit sodales. Donec nisi tortor, pretium sit amet nulla eu, hendrerit semper elit. Nunc turpis dui, dignissim vel urna et, commodo suscipit turpis. Mauris malesuada tortor at leo dictum suscipit. Nunc volutpat dignissim viverra. Fusce non nisl eu nisl ultrices bibendum vel eu libero.

Phasellus ornare massa lacus, ut accumsan nulla luctus quis. Phasellus vitae condimentum ligula, id maximus arcu. Vivamus sagittis varius scelerisque. Morbi tincidunt, elit at facilisis iaculis, dolor justo bibendum neque, a gravida felis neque dignissim magna. Duis et odio imperdiet, laoreet arcu vitae, consectetur nibh. Vivamus sollicitudin justo odio, molestie accumsan quam efficitur auctor. Praesent quis nibh lectus. Praesent porta augue arcu, quis eleifend ipsum sollicitudin eu. Interdum et malesuada fames ac ante ipsum primis in faucibus. Ut efficitur augue quam, quis dignissim odio hendrerit sed. Aliquam consequat leo non erat volutpat elementum. Aenean libero tortor, aliquam non ornare quis, vestibulum tristique justo. Quisque imperdiet euismod urna sit amet blandit. Donec a maximus enim.

This is a test

- One
- Two

> # Title in blockquote

``` swift
struct ArticleMetadata: Metadata {
  let tags: [String]
  let summary: String?
  let `public`: Bool?

  var isPublic: Bool {
    return `public` ?? true
  }
}
```

``` python
from django.db.models.signals import post_save
from staticgenerator import recursive_delete

def delete_cache(sender, **kwargs):
    recursive_delete('/')

post_save.connect(delete_cache)
```

``` javascript
function subscibe(priceId) {
  createStripeSession(priceId).then(result => {
    const sessionId = result.data;

    const stripe = Stripe("pk_live_XXX");
    stripe.redirectToCheckout({
      sessionId: sessionId,
    }).then(function (result) {
      console.log(result.error.message);
    });
  });
}
```
