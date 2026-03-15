-- 201. Є клієнти, в яких історія замовлень нерегулярна. Треба знайти тих, у кого було хоча би два замовлення,
-- і між якими є рівно один пропущений календарний місяць.

WITh level1 as(SELECT DISTINCT order_date 
       ,customer_id
       ,order_id
	   ,date_trunc('month', order_date) as date
FROm orders
JOIN order_details USING (order_id)
ORDER BY customer_id, order_date),
level2 as(SELECT customer_id
       ,order_id
       ,date
	   ,LAG(date) OVER (partition by customer_id order by date) as prev_date
FROM level1),
level3 as(SELECT *
       ,EXTRACT (year from age(date,prev_date)) * 12 + EXTRACT(month from age(date, prev_date)) as interval
FROM level2)
SELECT *
FROM level3
WHERE interval = 1

-- 202. “Клієнти з нічим не пояснюваними піками: знайти замовлення, де кількість товарів виросла мінімум у
-- 4 рази відносно історичного середнього клієнта”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity_per_customer
FROM level1),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / avg_quantity_per_customer::numeric),2) as ratio
FROm level2)
SELECT *
FROM level3
WHERE sum_quantity >= avg_quantity_per_customer * 4

-- 203. “Клієнти з дзеркально перевернутими трендами”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,order_id
       ,EXTRACT(year from order_date) as year
	   ,EXTRACT(month from order_date) as month
	   ,sum_quantity
	   ,sum_chek
FROM level1
ORDER BY customer_id, year, month),
level3 as(SELECT *
       ,case when month IN (1,2,3) THEN 1
	   when month IN (4,5,6) THEN 2
	   when month IN (7,8,9) THEN 3
	   when month IN (10,11,12) THEN 4
	   END as quartals
FROM level2),
level4 as(SELECT customer_id
       ,year
	   ,quartals
	   ,ROUND(AVG(sum_quantity)::numeric,2) as avg_quantity_per_quartal
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek_per_quartal
FROM level3
GROUP BY customer_id, year, quartals
ORDER BY customer_id, year, quartals),
level5 as(SELECT *
       ,LAG(avg_quantity_per_quartal) OVER (partition by customer_id order by year, quartals) as prev_avg_quantity_per_quartal
	   ,LAG(avg_chek_per_quartal) OVER (partition by customer_id order by year, quartals) as prev_avg_chek_per_quartal
FROM level4),
level6 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as real_count_order
FROM level5
WHERE prev_avg_chek_per_quartal is not null),
level7 as(SELECT *
       ,case when prev_avg_quantity_per_quartal < avg_quantity_per_quartal 
	   AND prev_avg_chek_per_quartal > avg_chek_per_quartal THEN 1
	   ELSE 0 END as flags
FROM level6),
level8 as(SELECT *
       ,SUM(flags) OVER (partition by customer_id) as sum_flags_per_customer
FROM level7)
SELECT *
FROM level8 
WHERE sum_flags_per_customer = real_count_order

-- 204. “Клієнти з аномальною залежністю від одного продукту”

WITH level1 as(SELECT customer_id
       ,order_id
       ,product_id
	   ,SUM(quantity)  as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, product_id, order_id),
level2 as(SELECT customer_id
       ,COUNT(*) as order_count
FROM orders
GROUP BY customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
ORDER BY customer_id),
level4 as(SELECT *
       ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity
FROM level3
WHERE order_count > 5),
level5 as(SELECT *
       ,ROUND((sum_quantity::numeric / total_quantity::numeric)*100,2) as percent
FROM level4),
level6 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id ORDER BY percent DESC) as rn
FROM level5),
level7 as(SELECT DISTINCT customer_id
       ,MAX(percent) OVER (partition by customer_id) as max_percent
	   ,MIN(percent) OVER (partition by customer_id) as min_percent
FROM level6
WHERE rn <= 2),
level8 as(SELECT *
       ,case when max_percent > 60 AND min_percent <= 20 THEN 'yes'
	   ELSE 'no' END as gradation
FROM level7)
SELECT *
FROM level8
WHERE gradation = 'yes'

-- 205. “Клієнти з парадоксом коротких довгих замовлень”

WITh level1 as(SELECT customer_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id
ORDER BY customer_id, order_id),
level2 as(SELECT *
       ,case when sum_quantity <= 20 THEN 'small_group'
	   when sum_quantity >= 50 THEN 'big_group'
	   ELSE 'other' END as gradation
FROM level1),
level3 as(SELECT customer_id 
    ,percentile_cont(0.5) within group (order by sum_chek) filter (where gradation = 'small_group') as median_chek_small_group
    ,percentile_cont(0.5) within group (order by sum_chek) filter (where gradation = 'big_group') as median_chek_big_group
FROM level2
WHERE gradation IN ('small_group','big_group')
GROUP BY customer_id)
SELECT *
FROM level3
where  median_chek_small_group > median_chek_big_group

-- 206. “Клієнти з категорією, яка є домінантною за кількістю товарних позицій у замовленнях,
-- але при цьому жодного разу не містила глобально найдорожчого товару цієї категорії

WITH level1 as(SELECT customer_id
       ,order_id
	   ,category_id
	   ,MAX(p.unit_price) as max_price
	   ,COUNT(DISTINCT category_id) as count_order
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING(product_id)
JOIN categories USING(category_id)
GROUP BY customer_id,order_id,category_id),
level2 as(SELECT customer_id
       ,category_id
	   ,MAX(max_price) as global_max_price
	   ,COUNT(count_order) as count_order_per_category
FROM level1
GROUP BY customer_id, category_id
ORDER BY customer_id, category_id),
level3 as(SELECT category_id
	   ,MAX(p.unit_price) as max_price_per_category
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING(product_id)
JOIN categories USING(category_id)
GROUP BY category_id),
level4 as(SELECT *
FROm level2
JOIN level3 USING(category_id)),
level5 as(SELECT *
       ,SUM(count_order_per_category) OVER (partition by customer_id) as total_order
FROM level4),
level6 as(SELECT *
       ,ROUND((count_order_per_category::numeric / total_order::numeric),2) as ratio
FROM level5)
SELECT *
FROM level6
WHERE ratio >= 0.5 AND global_max_price <> max_price_per_category

-- 207. “Клієнти зі зниклою улюбленою категорією”
-- Для кожного клієнта знайти категорію, яку він:
-- найбільше купував у першій половині своєї історії замовлень
-- (за кількістю order_id, де категорія з’явилась)
-- Але в другій половині історії клієнт взагалі жодного разу не купив цю категорію.

WITH level1 as(SELECT customer_id
       ,order_id
       ,order_date
	   ,category_name
	   ,COUNT(*) OVER (partition by customer_id) as count_item
	   ,ROW_number() OVEr (partition by customer_id order by order_date) as rn
	   ,COUNT(*) OVER (partition by customer_id) / 2 as middle_point
FROM orders
JOIn order_details USING(order_id)
JOIN products USING(product_id)
JOIn categories USING (category_id)),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROm level1),
level3 as(SELECT customer_id
       ,category_name
	   ,COUNT(distinct order_id) FILTER (where halfs = 'first_half') as count_fir_half
	   ,COUNT(distinct order_id) FILTER (where halfs = 'second_half') as count_sec_half
FROM level2
GROUP BY customer_id,category_name),
level4 as(SELECT *
       ,MAX(count_fir_half) OVER (partition by customer_id) as max_count_fir_half
	   ,MIN(count_sec_half) OVER (partition by customer_id) as min_count_sec_half
FROm level3)
SELECT *
FROM level4
where min_count_sec_half = 0