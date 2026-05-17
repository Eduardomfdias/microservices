from locust import HttpUser, task, between
import random

PRODUCT_IDS = [
    "OLJCESPC7Z", "66VCHSJNUP", "1YMWWN1N4O",
    "L9ECAV7KIM", "2ZYFJ3GM2N", "0PUK6V6EV0",
    "LS4PSXUNUM", "9SIQT8TOJO", "6E92ZMYYFZ"
]

CHECKOUT_FORM = {
    "email": "test@asid.uc.pt",
    "street_address": "123 Main St",
    "zip_code": "10001",
    "city": "New York",
    "state": "NY",
    "country": "United States",
    "credit_card_number": "4432801561520454",
    "credit_card_expiration_month": "1",
    "credit_card_expiration_year": "2030",
    "credit_card_cvv": "672"
}

class CasualUser(HttpUser):
    """30% do tráfego — utilizador casual: browse e homepage, raramente cart"""
    weight = 3
    wait_time = between(5, 15)

    @task(10)
    def browse_product(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.get(f"/product/{pid}", name="/product/[id]")

    @task(1)
    def index(self):
        self.client.get("/")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD", "GBP"])})


class NormalUser(HttpUser):
    """50% do tráfego — utilizador normal: browse, cart, checkout ocasional"""
    weight = 5
    wait_time = between(2, 6)

    @task(10)
    def browse_product(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.get(f"/product/{pid}", name="/product/[id]")

    @task(2)
    def add_to_cart(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.post("/cart",
                         data={"product_id": pid, "quantity": "1"},
                         name="/cart [add]")

    @task(3)
    def view_cart(self):
        self.client.get("/cart")

    @task(1)
    def checkout(self):
        pid = random.choice(PRODUCT_IDS)
        # Garante item no carrinho antes do checkout
        with self.client.post("/cart",
                              data={"product_id": pid, "quantity": "1"},
                              name="/cart [add]",
                              catch_response=True) as r:
            if r.status_code != 200:
                r.failure(f"add falhou ({r.status_code}), skip checkout")
                return
        self.client.post("/cart/checkout", data=CHECKOUT_FORM,
                         name="/cart/checkout")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD", "GBP", "JPY"])})

    @task(1)
    def index(self):
        self.client.get("/")


class PowerUser(HttpUser):
    """20% do tráfego — utilizador frequente: produto → cart → checkout"""
    weight = 2
    wait_time = between(0.5, 2)

    @task(10)
    def browse_product(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.get(f"/product/{pid}", name="/product/[id]")

    @task(3)
    def add_to_cart(self):
        pid = random.choice(PRODUCT_IDS)
        self.client.post("/cart",
                         data={"product_id": pid, "quantity": "1"},
                         name="/cart [add]")

    @task(3)
    def view_cart(self):
        self.client.get("/cart")

    @task(2)
    def checkout(self):
        pid = random.choice(PRODUCT_IDS)
        with self.client.post("/cart",
                              data={"product_id": pid, "quantity": "1"},
                              name="/cart [add]",
                              catch_response=True) as r:
            if r.status_code != 200:
                r.failure(f"add falhou ({r.status_code}), skip checkout")
                return
        self.client.post("/cart/checkout", data=CHECKOUT_FORM,
                         name="/cart/checkout")

    @task(2)
    def set_currency(self):
        self.client.post("/setCurrency",
                         data={"currency_code": random.choice(["EUR", "USD"])})
