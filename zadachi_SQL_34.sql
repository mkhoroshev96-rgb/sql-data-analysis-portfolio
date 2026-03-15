-- 208. Знайди всі замовлення, де є хоч один товар зі знижкою > 0.2.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,discount
	   ,MAX(discount) OVER (partition by customer_id order by order_date) as max_discount
FROm orders
JOIN order_details USING(order_id))
SELECT *
FROM level1
WHERE discount > 0.2

-- 209. Знайди клієнтів, які жодного разу не купували товар зі знижкою 
-- (тобто в усіх їхніх order_details discount = 0).

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,discount
	   ,count(*) OVER (partition by customer_id, order_id order by order_date) as count_item_per_order
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT *
       ,case when discount = 0 THEN 1
	   ELSE 0 END as flag
FROM level1),
level3 as(SELECT *
       ,SUM(flag) OVER (partition by customer_id) as sum_flag
	   ,count(count_item_per_order) over (partition by customer_id) as sum_count_item
FROM level2)
SELECT DISTINCT customer_id
FROM level3
WHERE sum_flag = sum_count_item

-- 210. Знайди всі замовлення, де:
-- мінімальна кількість quantity серед товарів у замовленні = 1
-- але максимальна quantity у цьому ж замовленні ≥ 10

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,quantity
	   ,MAX(quantity) OVER (partition by customer_id, order_id order by order_date) as max_quantity
	   ,MIN(quantity) OVER (partition by customer_id, order_id order by order_date) as min_quantity
FROM orders
JOIN order_details USING(order_id))
SELECT *
FROM level1
WHERE max_quantity >= 10 AND min_quantity = 1

-- 211. Знайди клієнтів, у яких є:
-- хоча б одне замовлення на менше ніж 50$
-- і хоча б одне інше замовлення на більше ніж 500$

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROm level1)
SELECT *
FROM level2
WHERE max_chek > 500 AND min_chek < 50

-- 212. Знайди таких клієнтів, у яких:
-- середній чек за всі замовлення > 200$,
-- але при цьому більш ніж половина їхніх замовлень мають чек < 100$.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_per_customer
FROM level1),
level3 as(SELECT *
       ,case when sum_chek < 100 THEN 1 ELSE 0 END as flag_chek_100
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level2),
level4 as(SELECT *
       ,SUM(flag_chek_100) over(partition by customer_id) as sum_flag_chek_100
FROM level3),
level5 as(SELECT *
       ,ROUND((sum_flag_chek_100::numeric / count_order::numeric),2) as ratio
FROM level4)
SELECT *
FROM level5
WHERE avg_chek_per_customer > 200 AND ratio > 0.5

-- 213. Потрібно знайти клієнтів, у яких:
--найпопулярніша категорія за кількістю товарів (quantity) ≠
--найприбутковіша категорія за сумою revenue (unit_price * quantity * (1–discount))

WITH level1 as(SELECT customer_id
       ,category_name
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::Numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING(product_id)
JOIN categories USING(category_id)
GROUP BY customer_id, category_name
ORDER BY customer_id, category_name),
level2 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
FROM level1),
level3 as(SELECT *
	   ,dense_rank() OVER (partition by customer_id order by sum_quantity DESC) as rn_quantity
	   ,dense_rank() OVER (partition by customer_id order by sum_chek DESC) as rn_chek 
FROM level2),
level4 as(SELECT *
FROM level3
where rn_quantity <> rn_chek)
SELECT *
FROm level4
WHERE rn_quantity = 1 OR rn_chek = 1

-- 214. Потрібно знайти клієнтів, у яких:
-- сумарний обсяг покупок (quantity) у літні місяці (6,7,8)
-- більший мінімум у 2 рази за сумарний обсяг покупок у зимові місяці (12,1,2).
-- І при цьому:у зимовий період вони робили не нуль замовлень (щоб уникнути ділення на 0 та пустих даних)

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,EXTRACT(month from order_date) as month
FROM level1),
level3 as(SELECT *
       ,case when month IN (6,7,8) THEN 'summer_season'
	   when month IN(1,2,12) THEN 'winter_season'
	   ELSE 'other' END as seasons
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(SUM(sum_quantity) FILTER (where seasons = 'summer_season')::numeric,2) as total_quantity_summer
	   ,ROUND(SUM(sum_quantity) FILTER (where seasons = 'winter_season')::numeric,2) as total_quantity_winter
FROM level3
WHERE seasons IN ('summer_season', 'winter_season')
GROUP BY customer_id),
level5 as(SELECT *
FROM level4
WHERE total_quantity_summer is not null AND total_quantity_winter is not null)
SELECT *
FROM level5
WHERE total_quantity_summer > total_quantity_winter * 2

-- 215. Знайди клієнтів, у яких:
-- середній чек замовлень зі знижкою > 0 вищий, ніж
-- середній чек замовлень без знижки (discount = 0).

WITH level1 as(SELECT customer_id
       ,order_id
	   ,discount
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT *
       ,case when discount = 0 THEN 'no_disc'
	   ELSE 'yes_disc' END as flag_discount
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(chek) FILTER (where flag_discount = 'no_disc')::numeric,2) as avg_chek_no_disc
	   ,ROUND(AVG(chek) FILTER (where flag_discount = 'yes_disc')::numeric,2) as avg_chek_yes_disc
FROM level2
GROUP BY customer_id),
level4 as(SELECT *
FROM level3
where avg_chek_no_disc is not null AND avg_chek_yes_disc is not null)
SELECT *
FROM level4
WHERE avg_chek_yes_disc > avg_chek_no_disc

-- 216. Знайди клієнтів, у яких:
-- замовлення з НАЙВИЩОЮ середньою ціною товару (unit_price * (1–discount)) НЕ співпадає з
-- замовленням з НАЙВИЩОЮ кількістю товарів (SUM(quantity))

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,MAX(avg_price) OVER (partition by customer_id) as max_price_per_order
	   ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity_per_order
	   ,dense_rank() OVER (partition by customer_id order by avg_price DESC) as rn_price
	   ,dense_rank() OVER (partition by customer_id order by sum_quantity DESC) as rn_quantity
FROM level1),
level3 as(SELECT *
FROM level2
WHERE rn_price <> rn_quantity),
level4 as(SELECT *
FROM level3
WHERE rn_price = 1 OR rn_quantity = 1)
SELECT *
FROM level4

-- 217. Для кожного клієнта:
-- Поділи всі його замовлення на першу половину та другу половину життя клієнта
-- (за order_date, як у твоїй задачі про “падіння активності”).
-- Для кожної половини знайди топ-1 категорію за сумою revenue
-- (revenue = unit_price * quantity * (1 – discount)).
-- Знайди клієнтів, у яких топова категорія у першій половині ≠ топовій категорії у другій половині.
-- Тобто клієнт кардинально змінив свій фокус інтересу.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,category_name
	   ,ROUND((p.unit_price * quantity * (1-discount))::numeric,2) as total_revenue 
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
ORDER BY customer_id, order_id),
level2 as(SELECT DISTINCT order_date
       ,customer_id
	   ,order_id
FROM orders
JOIN order_details USING (order_id)),
level3 as(SELECT customer_id
       ,order_id
       ,order_date
	   ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,COUNT(*) OVER (partition by customer_id) / 2 as middle_point
FROM level2),
level4 as(SELECT *
       ,case when rn <= middle_point THEn 'first_half'
	   when rn > middle_point THEN 'second_half'
	   End as halfs
FROM level3),
level5 as(SELECT l1.order_id
       ,l1.customer_id
	   ,l1.order_date
	   ,l1.category_name
	   ,l1.total_revenue
	   ,l4.count_order
	   ,l4.halfs
FROM level1 l1
JOIN level4 l4 USING (order_id)),
level6 as(SELECT customer_id
       ,category_name
       ,SUM(total_revenue)  FILTER (WHERE halfs = 'first_half') as sum_revenue_per_fir_half
	   ,SUM(TOTAL_revenue) FILTER (where halfs = 'second_half') as sum_revenue_per_sec_half
FROM level5
GROUP BY customer_id, category_name
ORDER BY customer_id),
level7 as(SELECT customer_id
       ,category_name as category_first
	   ,sum_revenue_per_fir_half
       ,dense_rank () Over (partition by customer_id order by sum_revenue_per_fir_half DESC) as rank_first
	   ,category_name as category_second
	   ,sum_revenue_per_sec_half
	   ,dense_rank () Over (partition by customer_id order by sum_revenue_per_sec_half DESC) as rank_second
FROM level6
where sum_revenue_per_fir_half is not null and sum_revenue_per_sec_half is not null),
level8 as(SELECT *
FROM level7
WHERE rank_first <> rank_second)
SELECT *
FROM level8
WHERE rank_first = 1 OR rank_second = 1




