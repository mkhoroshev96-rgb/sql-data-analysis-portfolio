-- 139. Знайди клієнтів, у яких середній чек падав два рази поспіль (pattern ↓ ↓).

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as avg_chek
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING(product_id)
GROUP BY customer_id,order_id),
level2 as(SELECT *
       ,LAG(avg_chek) OVER (partition by customer_id order by order_id) as prev_avg_chek
FROM level1),
level3 as(SELECT *
       ,case when prev_avg_chek > avg_chek THEN 1 ELSE 0 END as low_flag
FROM level2),
level4 as(SELECT *
       ,LAG(low_flag) OVER (partition by customer_id order by order_id) as prev_low_flag
FROM level3),
level5 as(SELECT *
       ,case when low_flag=1 AND prev_low_flag=1 THEN 1 ELSE 0 END as pattern_flag
FROM level4)
SELECT customer_id
       ,SUM(pattern_flag) as sum_pattrn_flag
FROm level5
GROUP BY customer_id
HAVING SUM(pattern_flag) >= 2 

-- 140. Знайди топ-3 категорії товарів за середньою прибутковістю 
-- (average revenue per order),але враховуй тільки ті категорії, які мають не менше 20 замовлень.

WITH level1 as(SELECT category_name
       ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_order_per_order
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING(product_id)
JOIN categories USING(category_id)
GROUP BY category_name,order_id),
level2 as(SELECT category_name
       ,ROUND(AVG(sum_order_per_order)::numeric,2) as avg_revenue_per_order
	   ,COUNT(*) as count_orders
FROM level1
GROUP BY category_name)
SELECT *
FROM level2
WHERE count_orders >= 20
ORDER BY avg_revenue_per_order DESC
LIMIT 3

-- 141.Знайди постачальників (suppliers), які продають щонайменше 3 різні продукти,
-- але сумарний обсяг продажів (в штуках) для кожного з цих продуктів
-- перевищує середнє значення по всіх продуктах цього постачальника.

WITH level1 as(SELECT supplier_id
       ,COUNT(DISTINCT product_id) as count_unir_product
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN suppliers USING(supplier_id)
GROUP BY supplier_id
HAVING COUNT(DISTINCT product_id) >= 3),
level2 as(SELECT supplier_id
       ,product_id
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN suppliers USING(supplier_id)
GROUP BY supplier_id,product_id
ORDER BY supplier_id, product_id),
level3 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER (partition by supplier_id)::numeric,2) as avg_quantity_per_supplier
FROM level1
JOIN level2 USING(supplier_id)),
level4 as (SELECT *
       ,COUNT(*) over (partition by supplier_id) as end_count
FROM level3
WHERE sum_quantity > avg_quantity_per_supplier)
SELECT *
FROm level4
WHERE end_count >= 3

-- 142. Знайди категорії товарів, для яких:
-- середня ціна товару (unit_price) вище середньої ціни по всіх категоріях
-- СУМА обсягів продажів (в штуках, SUM(quantity)) нижча за середню по всіх категоріях
-- а відсоток знижок (average discount) вищий за середній discount по всіх продуктах

WITH level1 as(SELECT category_id
       ,category_name
	   ,ROUND(AVG(p.unit_price)::numeric,2) as avg_price
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING(product_id)
JOIN categories USING(category_id)
GROUP BY category_id,category_name),
level2 as(SELECT *
       ,ROUND((SELECT AVG(discount) FROM order_details)::numeric,4) as avg_avg_discount
	   ,ROUND(AVG(sum_quantity) OVER ()::numeric,2) as avg_sum_quantity
	   ,ROUND((SELECT avg(unit_price) FROM products)::numeric,2) as avg_avg_price
FROM level1)
SELECT *
FROM level2
WHERE avg_price > avg_avg_price AND sum_quantity < avg_sum_quantity AND avg_discount > avg_avg_discount

-- 143. Знайти пари продуктів, які часто купують разом в одному замовленні.Але із важливою умовою:
-- Повернути тільки ті пари продуктів, які були разом в одному замовленні мінімум у 3 різних order_id.

WITH level1 as(SELECT order_id
       ,product_id
FROM order_details 
JOIN products USING(product_id)),
level2 as(SELECT t1.order_id as orderrr
       ,t1.product_id as prod_1
	   ,t2.product_id as prod_2
FROM level1 t1
JOIN level1 t2 on t1.order_id = t2.order_id AND t1.product_id < t2.product_id)
SELECT prod_1
       ,prod_2
       ,COUNT(DISTINCT orderrr) as count_orders
FROM level2
GROUP BY prod_1, prod_2
HAVING COUNT(DISTINCT orderrr) >= 3