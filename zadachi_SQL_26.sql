-- 155. “Клієнти, які зробили тільки одне замовлення”

WITH level1 as(SELECT DISTINCT order_id
       ,customer_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIn order_details USING(order_id)
GROUP BY order_id,customer_id),
level2 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as count_order
FROM level1)
SELECT *
FROM level2
WHERE count_order=1

-- 156. “Середній чек клієнта до його найдорожчого замовлення включно”

WITH level1 as(SELECT customer_id
       ,order_id
       ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,MAX(sum_chek) OVER(partition by customer_id) as max_sum_chek
FROm level1),
level3 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum_chek
	   ,ROW_number() OVER (partition by customer_id order by sum_chek DESC, order_date ASC) as rn
FROm level2),
level4 AS (
   SELECT l2.*,
          l3.order_date AS max_order_date
   FROM level2 l2
   JOIN level3 l3 USING(customer_id)
   WHERE l3.rn = 1),
level5 as(SELECT *
       ,case when order_date <= max_order_date THEN 'yes' ELSE 'no' END as yes_no
FROM level4)
SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level5
WHERE yes_no = 'yes'
GROUP BY customer_id
ORDER BY avg_chek DESC

-- моє рішення(результат блять однаковий - чатік тупо доїбався)

WITH level1 as(SELECT customer_id 
               ,order_date 
			   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek 
			   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn 
FROm orders JOIN order_details USING(order_id) 
GROUP BY customer_id,order_date), 
level2 as(SELECT * 
                 ,MAX(sum_chek) OVER(partition by customer_id) as max_sum_chek
FROm level1), 
level3 as(SELECT customer_id 
                 ,MAX(order_date) OVER (partition by customer_id) as max_order_date 
FROm level2 WHERE sum_chek = max_sum_chek), 
level4 as(SELECT *  
                 ,case when order_date <= max_order_date THEn 'yes' ELSE 'no' END as y_n 
FROM level2 
JOIN level3 USING(customer_id)) 
SELECT customer_id 
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek 
FROM level4 WHERE y_n = 'yes' 
GROUP BY customer_id 
ORDER BY avg_chek DESC

-- 157. “Клієнти з падінням активності: чи впав середній чек у другій половині життя клієнта?”

WITH level1 as(SELECT customer_id
	   ,order_date
       ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as ranks
	   ,count(*) OVER (partition by customer_id) as count_order
	   ,count(*) OVER (partition by customer_id) / 2 as middle_point
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_date),
level2 as(SELECT *
       ,case when ranks <= middle_point THEN 'first_half'
	   when ranks > middle_point THEN 'second_half'
	   END as halfs
FROM level1),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (where halfs = 'first_half')::numeric,2) as avg_chek_first_half
	   ,ROUND(AVG(sum_chek) FILTER (where halfs = 'second_half')::numeric,2) as avg_chek_second_half
FROM level2
GROUP BY customer_id)
SELECT customer_id
       ,avg_chek_second_half - avg_chek_first_half as diff
FROM level3
ORDER BY diff 
LIMIT 10

-- 158. «Знайди товари, які продаються суттєво гірше за інші у своїй категорії.»

WITH level1 as(SELECT product_id
       ,product_name
	   ,category_id
	   ,category_name
	   ,(SUM(quantity)) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
JOIN categories USING (category_id)
GROUP BY product_id,product_name,category_id,category_name),
level2 as(SELECT category_id
       ,category_name
       ,ROUND(AVG(sum_quantity)) as avg_qnt_per_category
FROM level1
GROUP BY category_id, category_name),
level3 as(SELECT l1.*
       ,l2.avg_qnt_per_category
FROM level1 l1
JOIN level2 l2 USING(category_id))
SELECT *
FROM level3
WHERE sum_quantity < avg_qnt_per_category * 0.5

-- 159. «Знайди клієнтів, чиї замовлення стають дедалі більшими:
-- кожне наступне замовлення має суму більшу, ніж попереднє.»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > prev_chek THEN 1 ELSE 0 END as high_chek
FROm level2),
level4 as(SELECT *
       ,SUM(high_chek) OVER (partition by customer_id) as sum_high_chek
       ,count_order - 1 as real_count_order
FROm level3
WHERE prev_chek is not null)
SELECT *
FROm level4
WHERE real_count_order > 1 AND sum_high_chek = real_count_order