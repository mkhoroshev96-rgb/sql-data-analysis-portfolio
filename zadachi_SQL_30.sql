-- 182. Знайти топ-3 постачальників із найвищою середньою ціною товарів, які вони постачають.

SELECT supplier_id
       ,company_name
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
FROM products
JOIN suppliers USING(supplier_id)
JOIN categories USING(category_id)
GROUP BY supplier_id,company_name
ORDER BY avg_price DESC
LIMIT 3

-- 183. Знайти товари, unit_price яких вище за середню ціну в їхній категорії більш ніж на 40%.

WITH level1 as(SELECT product_id
       ,product_name
	   ,category_name
	   ,unit_price
FROM products
JOIN suppliers USING(supplier_id)
JOIN categories USING(category_id)),
level2 as(SELECT *
       ,ROUND(AVG(unit_price) OVER (partition by category_name)::numeric,2) as avg_price_in_category
FROM level1),
level3 as(SELECT *
       ,ROUND((unit_price / avg_price_in_category)::numeric,2) as ratio
FROM level2)
SELECT *
FROM level3
WHERE ratio > 1.4

-- 184. Знайти клієнтів, у яких кожне наступне замовлення має більший середній чек, ніж попереднє.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id,order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > prev_chek THEN 1 ELSE 0 END as flag_chek
	   ,COUNT(*) OVER (partition by customer_id) as real_count_order
FROM level2
WHERE prev_chek is not null),
level4 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level3)
SELECT *
FROM level4
WHERE real_count_order = sum_flag_chek

-- 185. Потрібно знайти клієнтів, у яких середній чек по місяцях відрізняється менше ніж
-- на 10% від їхнього глобального середнього чека.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,EXTRACT(month from order_date) as month
	   ,EXTRACT(year from order_date) as year
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, EXTRACT(month from order_date), EXTRACT(year from order_date)),
level2 as(SELECT customer_id
       ,year
	   ,month
	   ,sum_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id, year, month)::numeric,2) as avg_mountly_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,ROUND((avg_mountly_chek / global_avg_chek)::numeric,2) as ratio
FROM level2),
level4 as(SELECT *
       ,case when ratio >= 0.9 AND ratio <= 1.1 THEN 1 ELSE 0 END as flag_customer
	   ,COUNT(*) OVER (partition by customer_id) as count_orders
FROM level3),
level5 as(SELECT *
       ,SUM(flag_customer) OVER (partition by customer_id) as sum_flag
FROM level4)
SELECT *
FROm level5
WHERE count_orders = sum_flag

-- 186. Розділити клієнтів на три категорії за стабільністю їхнього місячного 
-- середнього чека відносно глобального середнього.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,EXTRACT(year from order_date) as year
	   ,EXTRACT(month from order_date) as month
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id, EXTRACT(year from order_date), EXTRACT(month from order_date))::numeric,2) as avg_mountly_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as global_avg_chek
FROM level1),
level3 as(SELECT *
       ,ROUND((avg_mountly_chek / global_avg_chek)::numeric,2) as ratio
FROM level2),
level4 as(SELECT customer_id
       ,MAX(ratio) as max_ratio
	   ,MIN(ratio) as min_ratio
FROM level3
GROUP BY customer_id),
level5 as(SELECT *
       ,max_ratio - min_ratio as spread
FROM level4)
SELECT *
       ,case when spread <= 0.1 THEN 'high_stable'
	   when spread > 0.1 AND spread <= 0.25 THEN 'mediaum_stable'
	   when spread > 0.25 THEN 'unstable'
	   END as gradation
FROM level5

-- 187. Деякі клієнти, роблячи замовлення, спочатку купують найдорожчі товари, а вже потім — дешевші.
-- Ми хочемо знайти замовлення, у яких товари відсортовані за ціною в строгому спаданні

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND((unit_price * (1-discount))::numeric,2) as price_position_in_order
	   ,COUNT(*) OVEr (partition by order_id) as count_pos_in_order
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id,order_id),
level2 as(SELECT *
       ,LAG(price_position_in_order) OVER (partition by customer_id, order_id) as prev_price_pos_in_order
FROM level1
WHERE count_pos_in_order > 1),
level3 as(SELECT *
       ,case when price_position_in_order < prev_price_pos_in_order THEN 1 ELSE 0 END as flag_price
	   ,count_pos_in_order - 1 as real_count_pos_in_order
FROm level2
WHERE prev_price_pos_in_order is not null),
level4 as(SELECT *
       ,SUM(flag_price) OVER (partition by customer_id, order_id) as sum_flag
FROm level3)
SELECT *
FROM level4
WHERE real_count_pos_in_order = sum_flag

-- 188. “Клієнти з асиметрією інтересів: коли 1 категорія тягне весь чек”

WITH level1 as(SELECT customer_id
	   ,category_name
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP BY customer_id,order_id,category_name
ORDER BY customer_id),
level2 as(SELECT DISTINCT category_name
       ,customer_id
       ,SUM(sum_chek) OVEr (partition by customer_id, category_name) as total_in_category
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
ORDER BY customer_id, category_name),
level3 as(SELECT customer_id
       ,category_name
	   ,ROUND((total_in_category::numeric / total_revenue::numeric),2) as ratio
FROM level2),
level4 as(SELECT *
       ,ROW_number() OVEr (partition by customer_id ORDER BY ratio DESC) as rn
FROM level3),
level5 as(SELECT *
       ,MAX(ratio) OVER (partition by customer_id) as first_ratio
	   ,MIN(ratio) OVER (partition by customer_id) as second_ratio
FROM level4
where rn <= 2),
level6 as(SELECT *
       ,case when first_ratio > 0.7 AND second_ratio <= 0.2 THEN 'yes'
	   else 'other' END as flags
FROM level5)
SELECT *
FROM level6
WHERE flags = 'yes'

