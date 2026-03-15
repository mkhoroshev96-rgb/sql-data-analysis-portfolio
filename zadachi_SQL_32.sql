-- 196. Знайти топ-3 клієнтів за загальним виторгом (revenue), але:
-- рахувати revenue по всіх замовленнях клієнта;
-- ігнорувати знижку, тобто брати unit_price * quantity, а не ціну після знижки;
-- але вивести також їхній справжній виторг (з урахуванням знижки) у окремій колонці;
-- і обов’язково відсортувати за revenue без знижки, а не за реальним.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity)::numeric,2) as brutto_revenue_per_order
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as netto_revenue_per_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id)
SELECT customer_id
       ,SUM(brutto_revenue_per_order) as total_brutto_revenue
	   ,SUM(netto_revenue_per_order) as total_netto_revenue
FROM level1
GROUP BY customer_id
ORDER BY total_brutto_revenue DESC
LIMIT 3

-- 197. Клієнт живе в одній країні, але:
-- переважна більшість його замовлень доставляється в інші країни,
-- а саме — більше 70% замовлень мають ship_country ≠ customer.country.
-- І при цьому місто доставки (ship_city) хоча б у 2 різних країнах не 
-- збігається з customer.city (тобто клієнт виглядає так, ніби він оформлює для “чужих регіонів”).

WITH level1 as(SELECT customer_id
       ,order_id
       ,country
	   ,city
	   ,ship_country
	   ,ship_city
	   ,COUNT(*) OVER(partition by customer_id) as count_orders
FROM orders
JOIN customers USING(customer_id)
GROUP BY customer_id, order_id, country, city, ship_country, ship_city
ORDER BY customer_id, order_id)
SELECT *
FROM level1
WHERE count_orders >= 5 AND city <> ship_city

-- 198. Знайти клієнтів, у яких між будь-якими двома сусідніми замовленнями 
-- існує один (і тільки один!) аномальний розрив.

WITH level1 as(SELECT DISTINCT order_id
       ,customer_id
       ,order_date
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
FROM level1),
level3 as(SELECT customer_id
       ,order_id
	   ,order_date
       ,order_date - prev_date as interval
FROM level2),
level4 as(SELECT customer_id
       ,percentile_cont(0.5) WITHIN GROUP (order by interval) as median
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
FROM level3
JOIN level4 USING (customer_id)
WHERE interval is not null
ORDER BY customer_id, order_date),
level6 as(SELECT *
       ,ROUND((interval/median)::numeric,2) as diff
	   ,COUNT(*) OVER (partition by customer_id) as real_count_order
FROM level5),
level7 as(SELECT *
       ,case when diff < 0.8 OR diff > 1.2 THEN 1 ELSE 0 END flag_diff
FROm level6),
level8 as(SELECT *
       ,SUM(flag_diff) OVEr (partition by customer_id) as sum_flag_diff
FROm level7)
SELECT *
FROm level8
where  sum_flag_diff = 1

-- 199. Знайти клієнтів, у яких є рівно один “одинокий” вибрик:
-- Категорія, яку клієнт купив тільки в одному замовленні, і ця 
-- категорія ніколи більше не зустрічається в історії його покупок.

WITH level1 as(SELECT customer_id
	   ,category_name
	   ,COUNT(*) as count_orders
FROM orders
JOIN order_details USING(order_id)
JOIN products USING (product_id)
JOIN categories USING (category_id)
GROUP BY customer_id, category_name
ORDER BY customer_id),
level2 as(SELECT *
       ,dense_rank () OVER (partition by customer_id order by count_orders) as ranks
FROM level1),
level3 as(SELECT *
       ,COUNT(ranks) OVER (partition by customer_id) as count_rank_1
FROM level2
where ranks = 1)
SELECT *
FROM level3
WHERE count_rank_1 = 1 AND count_orders = 1

-- 200. “Клієнти з інверсією історії покупок”
-- Знайти клієнтів, у яких відбувається інверсія між двома поведінковими метриками:
-- 1) середній чек по замовленню (average order value)
-- 2) частота замовлень (orders per month)

WITH level1 as (SELECT DISTINCT order_date
       ,customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount)) OVER (partition by customer_id, order_id)::numeric,2) as sum_chek_per_order
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, order_id),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum_chek_per_order
       ,COUNT(*) OVER (partition by customer_id) as count_order
	   ,ROW_number() OVER (partition by customer_id) as rn
	   ,COUNT(*) OVER (partition by customer_id) / 2 as middle_point
FROM level1),
level3 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level2),
level4 as(SELECT customer_id
       ,COUNT(*) FILTER (where halfs = 'first_half') as count_1_half
	   ,COUNT(*) FILTER (where halfs = 'second_half') as count_2_half
       ,ROUND(AVG(sum_chek_per_order) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_1_half
	   ,ROUND(AVG(sum_chek_per_order) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_2_half
	   ,MAX(date_trunc('month', order_date)) FILTER (WHERE halfs = 'first_half') as max_date_1_half
	   ,MIN(date_trunc('month', order_date)) FILTER (WHERE halfs = 'first_half') as min_date_1_half
	   ,MAX(date_trunc('month', order_date)) FILTER (WHERE halfs = 'second_half') as max_date_2_half
	   ,MIN(date_trunc('month', order_date)) FILTER (WHERE halfs = 'second_half') as min_date_2_half
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,EXTRACT(year from age(max_date_1_half,min_date_1_half)) * 12 + EXTRACT(MONTH FROM age(max_date_1_half,min_date_1_half)) + 1 as interval_1_half
	   ,EXTRACT(year from age(max_date_2_half,min_date_2_half)) * 12 + EXTRACT(MONTH FROM age(max_date_2_half,min_date_2_half)) + 1 as interval_2_half
FROM level4),
level6 as(SELECT customer_id
       ,avg_chek_1_half
	   ,avg_chek_2_half
       ,ROUND((count_1_half::numeric / interval_1_half::numeric),2) as order_frequency_1_half
	   ,ROUND((count_2_half::numeric / interval_2_half::numeric),2) as order_frequency_2_half
FROM level5),
level7 as(SELECT *
       ,case when avg_chek_1_half > avg_chek_2_half AND order_frequency_1_half < order_frequency_2_half THEN 'anomaly_1'
	   when avg_chek_1_half < avg_chek_2_half AND order_frequency_1_half > order_frequency_2_half THEN 'anomaly_2'
	   ELSE 'other' END as flag_anomaly
FROM level6)
SELECT *
FROM level7
WHERE flag_anomaly IN ('anomaly_1','anomaly_2')


