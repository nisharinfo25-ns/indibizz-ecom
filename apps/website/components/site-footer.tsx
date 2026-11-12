import Link from "next/link";
import { APP_NAME } from "@indibizz/shared";

export function SiteFooter() {
  const year = new Date().getFullYear();
  return (
    <footer className="site-footer">
      <div className="container">
        <div className="footer-grid">
          <div className="footer-brand">
            <Link href="/" className="brand">
              <span className="brand-mark">IB</span>
              <span>
                IndiaBizz
                <small>Cash on delivery</small>
              </span>
            </Link>
            <p>
              A cash-on-delivery storefront with OTP-verified handover, sealed-package
              evidence and a transparent order trail from confirmation to delivery.
            </p>
          </div>

          <div className="footer-col">
            <h3>Shop</h3>
            <Link href="/shop">All products</Link>
            <Link href="/cart">Your cart</Link>
            <Link href="/orders">Your orders</Link>
          </div>

          <div className="footer-col">
            <h3>Account</h3>
            <Link href="/login">Sign in with phone</Link>
            <Link href="/account">Profile and addresses</Link>
            <Link href="/account#notifications">Notifications</Link>
          </div>

          <div className="footer-col">
            <h3>How COD works</h3>
            <p>Pay cash only after the parcel is handed over and checked.</p>
            <p>Share the delivery OTP only with the assigned delivery person.</p>
            <p>Returns follow the seller&apos;s published return window.</p>
          </div>
        </div>

        <div className="footer-bottom">
          <span>© {year} {APP_NAME}. All prices include applicable taxes where configured.</span>
          <span>Cash on delivery only • No card or prepaid checkout</span>
        </div>
      </div>
    </footer>
  );
}
